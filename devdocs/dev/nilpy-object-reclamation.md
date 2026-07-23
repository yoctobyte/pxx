# NilPy object reclamation — design note

Companion to the ticket `feature-nilpy-object-reclamation` (Track A, p55).
Written 2026-07-22 with the whole leak investigation warm; the five fixed
layers of `bug-a-runtime-variant-heap-grows-unbounded` are the context.

## Problem statement

NilPy class instances (TPyDict, TPyList, TPyBytes, user classes) and
bound-method pairs have no lifetime management: allocation is GetMem + ctor,
and nothing ever frees them. CPython reclaims by refcount. The measured
driver: uforth's `exec_python_inline` allocates an env dict + ns dict +
5 bound-method pairs per PYTHON-word call (~4-5 KB), all of whose references
die at method return — 20k-iter doloop peaks at 553 MB vs CPython's 24 MB.

The user's ruling (decide-uforth-exec-leak-strategy): uforth stays untouched;
the compiler must not leak. "Let leaks be due to application bugs, not
compiler errors."

## Hard constraints

1. **Pascal classes stay manual-Free.** FPC semantics; the compiler itself is
   built on them. NO blanket refcounting of tyClass. The discipline applies
   only to instances created by NilPy code paths and the pylib types that
   serve them.
2. **The isNilPy landmine** (project_pyeval_arc_state_and_wiring_blocker):
   `isNilPy` is a whole-compilation flag; NilPy-user-only emission rules must
   ALSO gate on `CurrentUnitIdx < 0`, or the rule leaks into pylib's own
   Pascal source and corrupts its manual memory handling.
3. **Self-host byte-identity.** Nothing here may change Pascal-mode codegen.
   Every emission change is behind the NilPy-user gate; the Pascal self-build
   must stay byte-identical by construction (the fpjson/uforth suites are the
   behavioral gate for the NilPy side).
4. **Threading.** Every new release path follows the heap-lock protocol
   (PXXStr* discipline, heap-size-class allocator). The FPC
   threaded-ansistring history is the cautionary tale — get the lock scope
   right on day one, not retrofitted.

## Where the refcount lives

Heap blocks already carry a refcount word at `[payload-16]` (the AnsiString
protocol; PXXStrIncRef/DecRef and the variant VT_STRING slot ARC use it).
Class instances come from the same allocator, so the SAME slot serves:
**rc(instance) at [instance-16]**, initialized to 1 by the allocation path
that feeds a NilPy constructor. No per-class layout change, no TSymbol
fields (project_tsymbol_field_landmine).

Bound-method pairs (pybound_new's {code, recv} heap pair) get the same
treatment — they are already heap blocks.

## Ownership rules (mirror the AnsiString ones exactly)

- Constructor result / factory call result: OWNED (+1), ownership transfers
  to whatever binds it. Same rule the string paths use, and the same
  discrimination IR_VAR_STORE/IR_STORE_SYM apply since the layer-5 fix: a
  CALL result is owned; an LVALUE source is shared and must retain.
- Binding stores retain the new, release the old, in retain-first order
  (self-assignment safe): NilPy-user tyClass local/field/param-slot stores,
  variant slots taking VT_OBJECT / VT_BOUNDMETHOD payloads, dict/list
  element stores.
- Scope exit releases tyClass locals (the EmitManagedLocalCleanup family —
  the variant/promo arms show the exact shape), gated NilPy-user only.
- rc hitting 0 destroys: run the type's finalizer, then free the block.

## Destruction must be recursive per type

- TPyList: release each slot payload (the VT_STRING arm exists; add
  VT_OBJECT/VT_BOUNDMETHOD), free the data block, free the instance.
- TPyDict: release keylist + vallist (TPyLists, themselves rc'd), free.
- TPyBytes: free the buffer, free.
- User classes: walk fields via the record layout descriptor
  (PXXRecordRelease's RTTI already walks managed fields — extend the walker
  with an object-slot arm) then free.

The finalizer dispatch can ride the existing VMT: a generated `__finalize__`
slot per NilPy class, pylib types providing hand-written ones.

## Cycles — explicitly out of scope

Refcount-only leaks cycles (vm ↔ word structures could form them). CPython
needs a cycle GC for the general case; we accept the FPC-grade contract:
acyclic graphs reclaim fully, cycles are the application's job (document
`weak`-style patterns if a corpus needs them). The uforth env-per-call
pattern is acyclic — refcounting alone reclaims ~all of the 553 MB.

## Slice ladder (each lands green on its own)

1. **Runtime primitives:** PXXObjRetain / PXXObjRelease(obj, finalizerVT) +
   rc=1 at NilPy construction. Nothing calls release yet — pure additive,
   zero behavior change. Gate: full suites unchanged.
2. **Variant-slot ARC for objects:** extend the existing VT_STRING slot
   retain/release arms (pylib pyvar copy helpers + IR_VAR_STORE/VAR arms) to
   VT_OBJECT / VT_BOUNDMETHOD. This alone frees the bound-method pairs and
   any dict-held objects whose slots are overwritten.
3. **Container finalizers:** TPyList/TPyDict/TPyBytes `__finalize__` +
   recursive slot release. Still nothing triggers destruction except slot
   overwrite from slice 2.
4. **Scope-exit release of NilPy-user tyClass locals** (the trigger that
   actually drains uforth's env/ns per call). Gate: doloop RSS bounded,
   the vbox/vstr probes stay flat, fpjson + uforth suites byte-identical.
5. **Field/param stores + user-class finalizers.** Sweep every sibling
   dispatch arm (feedback_sweep_sibling_dispatch_branches) — the store
   routes are exactly the None-sentinel route list in
   project_nilpy_none_routes_sentinels.

Order matters: 1-3 are inert scaffolding with full-suite gates; 4 is the
first observable behavior change and carries the risk; 5 completes the
contract. Park points between slices are safe (nothing half-owns).

## Verification set

Leak attribution tooling: **devdocs/dev/valgrind.md** (`-dPXX_LIBC_HEAP`
+ `tools/vgsym.py`) — memcheck sees every allocation with symbolized
stacks; 0 memcheck errors on the ARC probes as of 2026-07-23.

- `v = pick(i)` / vstr / vbox probes (umbrella ticket) stay flat.
- uforth: `make test-uforth`, the 4 suite drivers byte-identical vs CPython,
  `make bench-uforth` doloop RSS target < 40 MB.
- fpjson 203/203, test-nilpy, quick tier, self-host byte-identical.
- A double-free canary: shared instance in two locals, one overwritten in a
  loop — rc must keep the survivor alive (mirror of the string sharing test
  in test_nilpy_variant_str_boxing).
