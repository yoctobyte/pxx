---
track: A
prio: 55
type: feature
owner: fable-a-n
---

# NilPy object reclamation — dict/list/instance/bound-method lifetime

The user's resolution of [[decide-uforth-exec-leak-strategy]] (2026-07-22):
**uforth stays untouched** — it is a test case; improvement suggestions go to
the uforth repo itself, not here. The compiler must not leak on Python code:
"let leaks be due to application bugs, not compiler errors." So this is the
work item, and it must land either way.

## Current state
- Variant SLOT lifetime is handled: scope-exit release, ARC-correct
  var_store/copy, promo-tier clears, aggregate-dest release, call-result
  boxing ownership (the five fixed layers of
  [[bug-a-runtime-variant-heap-grows-unbounded]]).
- CLASS INSTANCES (TPyDict, TPyList, TPyBytes, user classes) and
  bound-method boxes have NO lifetime management at all: a dict whose
  binding dies is never freed. `xs = []` reassignment reclaims (special
  case); frame exit, dict-internal churn, and instance fields do not.

## The concrete driver
uforth's `exec_python_inline` allocates per PYTHON-word call: env TPyDict
{vm, push, pop, fpush, fpop} + ns TPyDict + 5 bound-method pairs + wrapper
string → ~4-5 KB/call orphaned. 20k-iter doloop = 553 MB peak vs CPython's
24 MB (`make bench-uforth` tracks it). Per-op RSS probes and the reduction
ladder live in the umbrella ticket.

## Shape (not decided here — implementation's call, escalate if forked)
Refcount class instances like AnsiString handles (retain on bind, release
on unbind/scope-exit, recursive release of variant-slot payloads/fields),
OR scope-tied arena for instances that provably don't escape. Watch: cycles
(vm ↔ words) — CPython solves with GC; a refcount-only scheme leaks cycles,
which for uforth's env-per-call pattern is still ~all of the 553 MB, so
refcounting is a legitimate first rung. The user's caution from FPC history
(threaded ansistring leaks): threading × memory management is hard — the
threadsafe heap lock discipline (heap-size-class allocator, PXXStr* lock
protocol) applies to every new release path.

Gate: uforth doloop RSS bounded and near-CPython; test-nilpy green;
self-host byte-identical; the vstr/vbox probes in the umbrella stay flat.

## Design pass done (fable-abcnp, 2026-07-22)

Full design in **devdocs/dev/nilpy-object-reclamation.md** — written while
the leak investigation was warm. Summary: rc in the existing heap-block
header word ([-16], the AnsiString protocol), ownership rules mirroring the
string ones (call results owned, lvalues retained — the layer-5
discrimination), recursive per-type finalizers via a VMT slot, cycles
explicitly out of scope (FPC-grade contract), everything behind the
NilPy-user gate (isNilPy AND CurrentUnitIdx<0 — the pyeval landmine).
Five-slice ladder, slices 1-3 inert/additive, slice 4 (scope-exit release
of NilPy tyClass locals) is the one that drains uforth's env-per-call and
carries the risk. Verification set in the doc. Pick up at slice 1.

## Progress (fable-a-n, night 2026-07-22/23)

Slices 1-4 LANDED (commits 0b39d0ea..HEAD): primitives + PXXObjAlloc
construction route (whole NilPy compilation, uniform headers, PXX_OBJ_MAGIC
population tag at [inst-8]); variant-slot ARC for VT_OBJECT/VT_BOUNDMETHOD
(x86-64 emitters via reg-preserving obj blobs, portable helpers for cross);
recursive finalizers (PXXObjFinalizeHook -> pylib PyObjFinalize; RAW magic for
bound pairs which own +1 on recv; class layout kind 5 = variant fields);
binding ARC + scope-exit release (owned = construction/call results via
return-retain; borrows retain; field-store ARC pulled forward; PXXObjPlausible
heap-envelope guard).

doloop RSS 595 -> 369 MB (as of the valgrind-profile night). Remaining tail to the <40 MB target:
- pyeval-side pinning (raw retains at PPyRec writes never released by pyeval's
  own storage; LclSet/globals lifetime)
- hidden desugar temps ('__py_*', '') excluded from ARC — their construction
  refs still leak (needs a mid-body zero-init story before they can join)
- class-typed FIELDS not walked by the finalizer (kind for tyClass fields +
  release in PyObjFinalize/PXXRecordRelease) — field refs leak on instance death
- aarch64 inline EmitVariantClearA64/RetainA64 lack the object arms (leak-only
  asymmetry; arm32/i386/rv32/xtensa go through portable PXXVarClear and are
  covered); scope-exit tyClass release arm is x86-64 only so far
- `d = None` (RHS non-class) stores raw — old binding's ref leaks
- shared instance in two locals canary test (verification set) not yet written

## Night follow-ups (2026-07-23, fable-a-n)

Landed since the slice-4 note: variant hidden-dest temp pre-call clear;
mid-body tyClass watermark zero-init (hidden temps join ARC); refcounted
pyeval closure objects (RAW2 magic + registry recycle stack, VT_PYCLOSURE=9
in all ARC arms); construction-in-arg spill to owning temp (pathIdx>=1).
doloop 595 -> 413 MB; plain container/bound-method churn probes flat.

NEXT (ranked):
1. **Literal-chain ownership**: list/dict literals lower as Self-returning
   chains (Create.append(a).append(b)); the chain result IS the receiver, so
   receiver-position constructions cannot be ARC-spilled (test_nilpy_forin
   regression showed why). Fix in pyparser: hoist `__py_t := Create` +
   append statements (PyHoistHead exists), yield the temp IDENT as the
   expression. Closes arg-position literal leaks (exec(src, {...}) 15 MB /
   20k probe; genexp-join wrapper build ~200 B/iter).
2. bug-n-pyeval-per-exec-leaks (see that ticket): ~24B/exec site-2 string +
   caller-side 64B with wrapper build.
3. Class-typed FIELDS in finalizer (kind for tyClass + release) — field refs
   leak on instance death.
4. aarch64 EmitVariantClearA64/RetainA64 object arms + non-x86 scope-exit
   tyClass release arm (leak-only asymmetry today).
5. `d = None` (RHS non-class) rebind leaks the old binding's ref.
