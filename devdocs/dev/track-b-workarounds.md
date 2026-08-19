# Track B — active workarounds awaiting a compiler fix

Registry of places where `lib/rtl` / `examples` code is written **non-idiomatically
to dodge an open Track A compiler bug**. When the listed bug moves to
`devdocs/progress/done/`, revert the workaround here and drop the entry.

Re-check each session against the latest pin (`stable_linux_amd64/default/pinned`):
the bugs get fixed fast. Verify the bug ticket is still in `backlog/`/`blocked/`
before assuming the workaround is still needed.

> Scope: only workarounds whose blocking bug is **still open**. Workarounds for
> already-fixed bugs (now in `done/`) are a separate cleanup pass — see the
> bottom section.

## Waiting on an open bug

| Where | Workaround | Blocking bug (open) | Revert to |
|---|---|---|---|
| `lib/rtl/math.pas` (`DdFloor`, `DdRint`) | `Double(Trunc(x))` where `Int(x)` is the natural spelling | [[bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32]] | `Int(x)` |
| `lib/rtl/bignum.pas` (`BigFromStr`, `BigDivMod`), `examples/bignum/bigmath.pas` | managed-return calls bound to a temp before being passed as an arg (no `BigAdd(BigMulSmall(x,…),…)` nesting) | [[bug-managed-record-result-self-arg]] (aka `bug-nested-managed-return-call-arg`) | nest the calls directly |
| `lib/rtl/chacha20poly1305.pas` (Poly1305) | native 5×26-bit limbs instead of `bignum` | [[bug-managed-record-result-self-arg]] — *partial:* limbs are the idiomatic choice anyway, so this is **not** a pure workaround; keep even after the fix | — (keep) |
| `lib/rtl/aesgcm.pas` (`BlkCopy`, used in `EncryptBlk`, `GfMul`, `AesCtr`, `GcmSetup`, `GcmTag`) | whole static-array `:=` replaced by element-copy loops | [[bug-fixed-array-assignment-no-copy]] — **fixed generally (v72)**, but a full revert of *this unit* still segfaults at the GCM path (residual, NOT minimally reproducible — every isolated `array :=` pattern passes on v72). **Keep `BlkCopy` here** until the residual is understood. | (do not revert yet) |
| `lib/pcl/mimic_reportlab_pdfgen.pas` (`Canvas.Create`) | TWO constructors — a one-arg form forwarding an EXPLICIT `0` — instead of one with `pagesize: Variant = 0` | [[bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory]] — a constructor with a defaulted Variant parameter smashes the stack when the caller omits it; deterministic from Pascal (25/25), intermittent through NilPy, and it surfaces as a crash in unrelated code | the single `pagesize: Variant = 0` default |
| `lib/rtl/ed25519.pas` (EC points) | a point's 4 field coords are **4 separate standalone TGf vars**, never an `array of TGf` or a record of TGf | [[bug-aggregate-member-array-as-var-param]] — passing an aggregate-member array by ref segfaults | a `TPoint = array[0..3] of TGf` / record |
| `lib/rtl/mimic_xml_sax_xmlreader.py` (`AttributesImpl.copy`, `AttributesNSImpl.copy`) | the class named explicitly where CPython writes `self.__class__(...)` | [[bug-n-self-class-cannot-be-called-as-a-constructor]] — calling `__class__` as a constructor does not compile; reading `self.__class__.__name__` is fine, only the call form fails | `self.__class__(...)` — and it is not cosmetic: only that form gives a SUBCLASS an instance of itself |
| `lib/rtl/math.pas` (`SinCosFast`, `FastTrigReduce`) | sin/cos returned in a `TSinCos` **record** by reference, and the reduction in a `TDd`, instead of `var sn, cs: Double` out-parameters | [[bug-a-i386-var-float-parameter-faults-on-first-access]] — ANY access through a by-reference float parameter segfaults on i386 (read, write, `out`, `Single`, every `-O` level); a record by reference is fine. Without this, the default-mode `Sin`/`Cos`/`Tan` crash on i386 | plain `var sn, cs: Double` — *but only if it reads better, which it does not:* the record mirrors `SinCosDd` and is the shape to keep |
| `lib/rtl/mimic_collections_abc.py` (every `Mapping`/`MutableMapping` mixin) | mixins walk `self.keys()` instead of `for k in self`, and each abstract method carries a dead `return iter([])` after its `raise` | [[bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides]] — `for k in self` inside a base method binds to the BASE `__iter__`, so a subclass override is never reached and the runtime reports `iter() returned non-iterator of type 'Sub'` | `for k in self`, and a bare `raise` with no trailing return |
| `lib/rtl/mimic_collections_abc.py` (`items`, `values`, `get`, `pop`, `setdefault`, `update`) | every internal subscript spelled `self.__getitem__(k)` / `self.__setitem__(k, v)` | [[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]] — the `[]` operator inside a base class binds statically to that class's own dunder; the explicit method call dispatches correctly | `self[k]` / `self[k] = v` |
| `lib/rtl/mimic_collections_abc.py` (`MutableMapping.update`) | mapping-vs-pairs discriminated by `isinstance(other, dict) or isinstance(other, Mapping)` | [[bug-n-hasattr-through-an-untyped-parameter-is-always-false]] — CPython leads with `hasattr(other, "keys")`, which answers False for *everything* reached through an untyped parameter, so a dict silently takes the pairs branch and `pair[0]` indexes a one-character string | the `hasattr(other, "keys")` test — and note the workaround is NARROWER than CPython: a duck-typed object with `keys()` and no `dict`/`Mapping` relation still lands in the pairs branch |
| `test/lib_mimic_collections_abc.npy` | `Mapping = cabc.Mapping` rebound at module top, then `isinstance(x, Mapping)` | [[bug-n-isinstance-does-not-accept-a-qualified-class-name]] — `isinstance(x, cabc.Mapping)` is a compile error (`unknown type in isinstance: cabc`) | `isinstance(x, cabc.Mapping)` — though the bare-name spelling is also what the corpus writes, so this one is close to cosmetic |

### Coding-pattern landmines (no single site — avoid in new Track B code)

- **A user class's `keys()` / `items()` / `values()` through a dynamically-typed
  receiver** (an unannotated parameter) segfaults, or answers a garbage list when
  the result is consumed — the call is dispatched as a dict view instead of the
  method ([[bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view]]).
  Exactly those three names; `get`/`append`/`insert`/`remove`/`clear`/`find`/`set`/
  `extend`/`pop` all dispatch correctly, and a *statically* typed receiver is fine.
  So a shim may still DEFINE them (`mimic_xml_etree_elementtree.Element` does) —
  do not CALL them through an untyped parameter. In library and test code reach the
  dict directly (`node.attrib.items()`), which is what html5lib does anyway.

- **`list(obj)` over an object with `__len__`/`__getitem__` and no `__iter__`
  returns `[]`**, silently, and `for x in obj` is a compile error naming an
  unrelated internal ([[bug-n-the-sequence-protocol-does-not-yield-iteration]]).
  Give any sequence-like NilPy class an explicit `__iter__` — that is exact rather
  than a workaround (CPython's C types carry `tp_iter` too), but it is not
  optional.

- **A function stored in a variable is not equal to the function.** `g = f` boxes
  it on the heap, so `g == f`, `g is f` and `h = f; g == h` are all False, and
  `id(g)` is a heap address where `id(f)` is the code address
  ([[bug-n-a-function-stored-in-a-variable-is-not-equal-to-the-function]]). A
  function used as a sentinel (CPython's `ElementTree.Comment` is its own tag)
  still works as long as both sides of the comparison come from a call result or
  the bare name — never from a variable holding it.

- **Long command-line arguments in a large program.** Reading a long `ParamStr`
  (~hundreds of chars) into an AnsiString and then doing more heap work corrupted
  memory and crashed later in `test/devtest_tls13_handshake.pas` (a big multi-unit
  program). Could **not** reduce to a minimal repro (`ParamStr` of a 700-char arg
  in isolation is fine), so no Track A ticket yet — but pass bulk data (a cert, a
  key) via a **file** (short path arg + `PalOpen`/`PalRead`), not argv. If a clean
  repro turns up, file it.

- **Managed-record return as a call arg.** Until
  [[bug-managed-record-result-self-arg]] is fixed, do not write
  `Result := F(Result, …)` or `g(F(x), …)` where the return type is a record with
  a managed field (dynamic array / AnsiString) — bind to a local first. Affects
  any `bignum`-heavy code (e.g. a future X25519/RSA written over `bignum` rather
  than fixed limbs).
- **`Read := x` / `Write := x`** (own-name result of an intrinsic-named **virtual**
  method) miscompiles — [[bug-virtual-keyword-name-result]]. Use `Result := x`.
- **Explicit `Int64(n)` where `n` is `NativeInt`/`NativeUInt`** does not extend on
  32-bit — it reinterprets 8 bytes and the high half is whatever was adjacent
  ([[bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit]]). The
  *implicit* widening (`q := n`) is correct, as is `Int64(@x)` / `Int64(ptr)`, so
  assign through an Int64 local rather than casting. The garbage MOVES with stack
  layout, so a passing site proves nothing about the one next to it.
- **Aggregate-member array as a var/const param** (a 2D-array row `p[i]`, or an
  array-typed record field `p.a`) segfaults —
  [[bug-aggregate-member-array-as-var-param]]. Keep each sub-array a standalone
  variable and pass them individually.

## Cleanup backlog — workarounds whose bug is now FIXED (revertible)

Low priority; do during a file pass, not their own session. Each references a bug
now in `done/`, so the workaround can be removed and the idiomatic form restored:

- `bug-string-ordering-comparison-constant` — `classes.pas` / `sysutils.pas` string
  relational-op avoidance.
- `bug-plain-byvalue-record-param-temp`, `bug-aarch64-record-temp-byvalue-arg` —
  `examples/raytracer` temp-arg avoidance (verify the aarch64 one's status; ticket
  file currently not found).
- `bug-proc-local-managed-record-uninit` — `examples/bignum/bigmath.pas` keeps all
  `TBigInt` locals in the main body.
- `bug-const-open-array-managed-elem-length` — `lib/rtl/menu.pas`.
- `bug-dynarray-in-record-corrupt` — `lib/rtl/sat.pas`.
- `bug-builtin-val-miscompiles` — `lib/rtl/sysutils.pas` (`Val` avoided).

## Recently unblocked (not a workaround — follow-up available)

- [[bug-proc-typed-call-const-record-arg]] **fixed (v70)** — a proc-typed value
  called with a `const record` arg (`arr[i](rec)`) now works. This unblocks
  **chess slice 2** (search + eval through `EvalTerms[i](pos)`); the demo was left
  blocked, not worked around, so nothing to revert — just resumable when chess is
  picked back up.

## Reverted 2026-08-17

- [[bug-n-a-type-as-a-default-parameter-value-segfaults-when-the-default-is-taken]]
  **fixed (`31172d1cc`, pinned v347 `f5da30bc9`)** — reverted
  `lib/rtl/mimic_warnings.py`'s `warn()` from `category=None` + a body
  substitution back to CPython's own `category=UserWarning`, and dropped the
  `if category is None` lines. Re-tested: `lib_mimic_warnings` 9/9 green.

  **The interval is the point, and it is the shortest one this table has
  recorded: filed, fixed and reverted inside one evening.** But it still took
  TWO events, not one — the fix landed on master at 22:19 and only reached
  Track B with the pin at 22:27, because B compiles with `$(PXX_STABLE)`, never
  HEAD. A revert fired between those two moments would have turned `make
  lib-test` red against a fix that already existed. So a row here is revertible
  when the **pin** carries the fix, which is a different question from whether
  the bug is fixed, and the only way to answer it is to re-run the repro against
  `pinned` — timestamps invite exactly the wrong inference, since the fix
  genuinely was in.

## Reverted 2026-06-25 (sis fixes, workarounds removed + re-tested)

- [[bug-not-on-int64-is-boolean]] **fixed (v71)** — reverted the `-x-1` /  `-b`
  bitwise-complement workaround back to plain `not` in `lib/rtl/x25519.pas`,
  `lib/rtl/ed25519.pas` (`Asr64`, `Sel25519`) and `lib/rtl/sha512.pas` (Ch).
  Re-tested: `lib_x25519` (6), `lib_sha512` (3), `lib_ed25519` (3) all green.
- [[bug-bare-read-write-in-method-hits-intrinsic]] **fixed (v71)** — reverted the
  `Self.Read`/`Self.Write` qualification in `lib/rtl/classes.pas` (`TStream`) to
  bare `Read`/`Write`. Re-tested: `lib_classes` (21) green.
- [[bug-managed-length-via-pointer-deref]] **fixed (v71)** — no Track B code
  carried a workaround (it was a compiler-internal find); landmine note dropped.
- [[bug-string-literal-concat-compare-segfault]] **fixed (v73)** — `x = 'a'+'b'`
  comparison no longer crashes (re-tested). The `lib_sha256`/`lib_aesgcm` expected
  hex literals were kept one-line; that form is fine, so nothing to revert.
- [[bug-fixed-array-assignment-no-copy]] **fixed (v72) for the general case** —
  every isolated `array :=` pattern (local↔local, ↔ var/const param, 16-elem)
  copies correctly. BUT reverting `lib/rtl/aesgcm.pas`'s `BlkCopy` to plain `:=`
  still **segfaults** in the GCM path (`aes-ecb` passes, `gcm-tc1` cores) and I
  could **not** minimally reproduce it. So `aesgcm` keeps `BlkCopy` for now (see
  the table above); the unit's behaviour is unchanged and `lib_aesgcm` stays green.
