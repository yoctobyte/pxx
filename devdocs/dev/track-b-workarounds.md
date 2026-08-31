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
>
> **Two sections, because a row leaves this one in two different ways.** Either
> the bug closes and the workaround comes out (→ *Reverted*, at the bottom), or
> the bug closes and the shape stays anyway because it reads better or because
> reverting it uncovered something else (→ *Deliberate keeps*, immediately
> below). A row that is not waiting on an open bug does not belong in the first
> table under any circumstances: on 2026-08-30 seven of its eight rows cited a
> closed ticket, three of them being deliberate keeps parked under a heading
> that asserted the opposite, and the section had stopped being read as a queue
> — which is how four live reverts sat there for weeks
> (`bug-b-seven-of-eight-workarounds-waiting-on-an-open-bug-are-waiting-on-nothing`).

## Waiting on an open bug

Three rows. The first two re-verified **by behaviour** at pin v393
(`1d69760deabe`) on 2026-08-30 — the repro was run, the folder was not consulted;
the third at pin v398 (`992065f21f33`) on 2026-08-31, same way.

| Where | Workaround | Blocking bug (open) | Revert to |
|---|---|---|---|
| `lib/rtl/ed25519.pas` (EC points) | a point's 4 field coords are **4 separate standalone TGf vars**, never an `array of TGf` or a record of TGf | [[bug-a-2d-array-row-as-a-const-array-param-still-segfaults]] — the parent [[bug-aggregate-member-array-as-var-param]] IS fixed for three of the four cells its own acceptance named (record field var + const, array row var, and `SizeOf` is right); the surviving cell is a 2D-array **row** passed as a **`const`** array param, which segfaults on all five targets. ed25519's field ops are `AddF(var o: TGf; const a, b: TGf)` and eleven more, so the natural revert passes `p[1]` as a `const TGf` — exactly the failing cell, confirmed with a shape-exact probe | a `TPoint = array[0..3] of TGf` / record |
| `lib/rtl/sysutils.pas` (`BigFCmpValue`) | the comparison body is a **top-level** function taking 8 parameters, instead of a routine nested inside `ExBinNearest` reading that routine's `TBigF` locals directly | [[feature-nested-routine-fixed-array-capture]] — **fixed at HEAD, not in the pin.** `50fcbddef` (2026-08-31 05:48) landed it; the ticket is still in `backlog/`. Re-verified by behaviour on pin v398 `992065f21f33`: an `array[0..3] of Integer` local to an enclosing procedure, read by a nested function, gives `error: nested routine: capture of fixed-size array 'a' not yet supported`, exit 1. **Beware the wrong repro shape** — a *program-level* array compiles and runs fine on the same binary, because that is a global and not a capture at all | nesting it inside `ExBinNearest`, once a pin carries `50fcbddef`. **Likely a *deliberate keep* rather than a revert:** the existing comment gives a second, independent reason — *"both callers wanted the same body regardless"* — so when the pin lands, judge it on that, and if it stands, move this row down to the section below rather than reverting |
| `lib/rtl/mimic_collections_abc.py` (`MutableMapping.update`) | mapping-vs-pairs discriminated by `isinstance(other, dict) or isinstance(other, Mapping)` | **BLOCKER CHANGED 2026-08-27** — the original one ([[bug-n-hasattr-through-an-untyped-parameter-is-always-false]]) is fixed and verified on v389: `hasattr(other, "keys")` now answers True for a dict and False for a list through an untyped parameter. The workaround stays for [[bug-n-keys-through-an-untyped-receiver-is-not-dispatched-cross-module]] instead — the branch that fixed test would select calls `other.keys()`, which segfaults from inside an imported module. The `isinstance` form is safe *because* both its branches iterate `other` directly and neither calls `keys()`. | CPython's three branches: `isinstance(other, Mapping)` → `elif hasattr(other, "keys")` → pairs. Still NARROWER than CPython until then: a duck-typed object with `keys()` and no `dict`/`Mapping` relation lands in the pairs branch |

## Deliberate keeps — the bug is fixed, the shape stays

**Not** waiting on anything. Each of these had its blocker close and is still
written this way on purpose; two of them will still be here after every bug in
this file is closed. They lived in the table above until 2026-08-30, which is a
large part of why that table stopped being read: a section that is mostly
not-actually-blocked rows does not reward a re-check.

| Where | Shape | Was blocked by | Why it stays |
|---|---|---|---|
| `lib/rtl/chacha20poly1305.pas` (Poly1305) | native 5×26-bit limbs instead of `bignum` | [[bug-managed-record-result-self-arg]] (fixed) | limbs are the idiomatic choice for Poly1305 anyway; this was never a pure workaround |
| `lib/rtl/aesgcm.pas` (`BlkCopy`, used in `EncryptBlk`, `GfMul`, `AesCtr`, `GcmSetup`, `GcmTag`) | whole static-array `:=` replaced by element-copy loops | [[bug-fixed-array-assignment-no-copy]] (fixed generally, v72) | a full revert of *this unit* still segfaults at the GCM path and is **not** minimally reproducible — every isolated `array :=` pattern passes. Keep until the residual is understood. This row is the model the others are measured against: a written, measured reason |
| `lib/rtl/math.pas` (`SinCosFast`, `FastTrigReduce`) | sin/cos returned in a `TSinCos` **record** by reference, and the reduction in a `TDd`, instead of `var sn, cs: Double` out-parameters | [[bug-a-i386-var-float-parameter-faults-on-first-access]] (fixed) | the record mirrors `SinCosDd` and is the shape to keep; reverting to `var sn, cs: Double` would read worse |

### Coding-pattern landmines (no single site — avoid in new Track B code)

- **A user class's `keys()` / `items()` / `values()` through a dynamically-typed
  receiver** (an unannotated parameter) segfaults, or answers a garbage list when
  the result is consumed — the call is resolved at the call site instead of
  dispatching on the receiver
  ([[bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view]], closed
  for the single-module case; **reopened across a module edge** as
  [[bug-n-keys-through-an-untyped-receiver-is-not-dispatched-cross-module]],
  measured on v389). Exactly those three names;
  `get`/`append`/`insert`/`remove`/`clear`/`find`/`set`/`extend`/`pop` all dispatch
  correctly, and a *statically* typed receiver is fine. So a shim may still DEFINE
  them (`mimic_xml_etree_elementtree.Element` does) — do not CALL them through an
  untyped parameter. In library and test code reach the dict directly
  (`node.attrib.items()`), which is what html5lib does anyway.

  **The trap in re-testing this one:** whether it bites depends on what the
  CALLING module declares, not on the call. A module that declares any simple
  `keys()` of its own dispatches correctly; one that declares none, or declares a
  `keys()` that iterates `self`, segfaults. So a probe written in a file that
  happens to contain a `keys()` passes and proves nothing — which is how the
  single-module close happened.

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

- ~~**Managed-record return as a call arg.**~~ **FIXED — landmine withdrawn
  2026-08-30.** `Result := F(Result, …)` and `g(F(x), …)` with a managed-field
  record return are fine; the ticket's own repro (`ViaResult`, `ViaLocal`, plus a
  doubly-nested form) runs 200/200 on x86-64, i386, arm32, riscv32 and aarch64 at
  pin v393. `bignum`-heavy code may nest freely — `lib/rtl/bignum.pas` was
  reverted to the nested form the same day. [[bug-managed-record-result-self-arg]]
- **`Read := x` / `Write := x`** (own-name result of an intrinsic-named **virtual**
  method) miscompiles — [[bug-virtual-keyword-name-result]]. Use `Result := x`.
- **Explicit `Int64(n)` where `n` is `NativeInt`/`NativeUInt`** does not extend on
  32-bit — it reinterprets 8 bytes and the high half is whatever was adjacent
  ([[bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit]]). The
  *implicit* widening (`q := n`) is correct, as is `Int64(@x)` / `Int64(ptr)`, so
  assign through an Int64 local rather than casting. The garbage MOVES with stack
  layout, so a passing site proves nothing about the one next to it.
- **A 2D-array ROW as a `const` array param** (`p[i]` where `p: array of TG`)
  segfaults, on all five targets —
  [[bug-a-2d-array-row-as-a-const-array-param-still-segfaults]]. **Narrowed
  2026-08-30 from the much wider claim this bullet used to make.** The three
  neighbouring forms all work now: the same row as a **`var`** param, and an
  array-typed **record field** `p.a` in either mode. `SizeOf` of the container
  is correct too. So the rule is no longer "keep every sub-array standalone" —
  it is: a row of a 2D array may be written through (`var`), but must not be
  passed as `const`. A record of arrays has no restriction at all and is the
  shape to reach for. Parent, for history:
  [[bug-aggregate-member-array-as-var-param]].

## Cleanup backlog — workarounds whose bug is now FIXED (revertible)

Low priority; do during a file pass, not their own session. Each references a bug
now in `done/`, so the workaround can be removed and the idiomatic form restored:

- `bug-string-ordering-comparison-constant` — `classes.pas` / `sysutils.pas` string
  relational-op avoidance.
- `bug-plain-byvalue-record-param-temp`, `bug-aarch64-record-temp-byvalue-arg` —
  `examples/raytracer` temp-arg avoidance (verify the aarch64 one's status; ticket
  file currently not found).
- ~~`bug-proc-local-managed-record-uninit` — `examples/bignum/bigmath.pas`~~
  **checked 2026-08-30: nothing to revert.** The bug is fixed (repro re-run on
  all five targets), and the program's shape is now an ordinary readability
  choice, not a constraint — in a checker, `chk := BigAddSigned(prod, r); if
  BigCompare(chk, a) <> 0` names the intermediate the FAIL message is about, and
  nesting it reads worse. Its header comment claimed a constraint and was
  corrected; the code stands.
- `bug-const-open-array-managed-elem-length` — `lib/rtl/menu.pas`.
- `bug-dynarray-in-record-corrupt` — `lib/rtl/sat.pas`.
- `bug-builtin-val-miscompiles` — `lib/rtl/sysutils.pas` (`Val` avoided).

## Recently unblocked (not a workaround — follow-up available)

- [[bug-proc-typed-call-const-record-arg]] **fixed (v70)** — a proc-typed value
  called with a `const record` arg (`arr[i](rec)`) now works. This unblocks
  **chess slice 2** (search + eval through `EvalTerms[i](pos)`); the demo was left
  blocked, not worked around, so nothing to revert — just resumable when chess is
  picked back up.

## Reverted 2026-08-30 (pin v393 `1d69760deabe`, verified against `$(PXX_STABLE)`)

Three of the four rows `bug-b-seven-of-eight-workarounds-waiting-on-an-open-bug-are-waiting-on-nothing`
identified as live reverts are gone; the fourth is still blocked, by a bug
nobody knew was still open.

- [[bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32]]
  **fixed** — `lib/rtl/math.pas`'s `DdRint` and `DdFloor` are back to `Int(x)`
  from `Double(Trunc(x))`. Verified on the two targets that HAD the bug, not
  just the ones that never did: the ticket's own repro (`Int(2^43 + 0.5)`) gives
  `8796093022208.00` on i386 and arm32 under qemu, where it used to give the two
  32-bit saturation constants. Then the public surface, `Sin`/`Cos` at ten
  magnitudes straddling 2^31, byte-identical across x86-64, i386, arm32, riscv32
  and aarch64 **and** exact against CPython/libm on all ten.
- [[bug-managed-record-result-self-arg]] **fixed** — `lib/rtl/bignum.pas`'s
  `BigFromStr` parse loop is one nested expression again
  (`r := BigAdd(BigMulSmall(r, 10), BigFromInt(d))`, was three statements through
  two temps) and `BigModPow`'s square-and-multiply passes its `BigMul` results
  straight in. Verified against **CPython's arbitrary-precision ints** — long
  decimal parse, a 39×29-digit product, and two modular exponentiations
  including a 128-bit modulus — identical on all five targets.
- [[bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory]] **fixed**
  — `lib/pcl/mimic_reportlab_pdfgen.pas`'s `Canvas` is back to ONE constructor
  with `pagesize: Variant = 0`, from two with a one-arg form forwarding an
  explicit `0`. The ticket's 12-line repro runs 25/25 clean, and through NilPy
  `canvas.Canvas("out.pdf")` — the omitted-argument call the workaround existed
  to protect — runs 50/50 with A4, letter and the default page all correct.

`make lib-test` green.

**What this batch adds to the two lessons below.** 2026-08-17 established that a
row is revertible when the **pin** carries the fix, not when the bug is fixed.
2026-08-27 added: **and the idiomatic form it unblocks actually runs.** This one
adds the third: **verify the capability, not the ticket's folder — and verify it
on the arm that was broken.**

Two of the four rows would have been got wrong by the obvious method:

- **Row 1 is invisible from Track B's own target.** Its bug was i386/arm32-only.
  Every probe run on x86-64 — the machine, the pin, the default build — passes
  identically whether the bug is fixed or not, so "I tested it and it works"
  would have been true and worthless. The revert is only justified because the
  repro was cross-compiled and run under qemu on the two targets that had it.
- **Row 4 (ed25519) is a ticket in `done/` whose capability does not work.**
  Its blocker's acceptance named four cells — 2D-array row and array-typed
  record field, `var` and `const`. Three pass. The fourth, a row as a **`const`**
  param, segfaults on all five targets, and it is the exact cell ed25519's revert
  needs, because its field ops are `const TGf`. Filed as
  [[bug-a-2d-array-row-as-a-const-array-param-still-segfaults]] and the row stays
  put. A folder is a filing decision; only the repro is evidence.

The general form, since this file keeps rediscovering it one variant at a time:
**every step between "the bug is fixed" and "this code can change" is a separate
claim, and each one has been the false one at least once.** Fixed on master ≠
in the pin (2026-08-17) ≠ the reverted code runs (2026-08-27) ≠ the capability
works at all (today) ≠ it works on the target that was broken (today).

## Reverted 2026-08-27 (pin v389 `325b4479070a`, verified against `$(PXX_STABLE)`)

Three of the four rows the 2026-08-26 note flagged as revertible are gone; the
fourth's blocker changed rather than closing.

- [[bug-n-self-class-cannot-be-called-as-a-constructor]] **fixed** —
  `lib/rtl/mimic_xml_sax_xmlreader.py`'s `AttributesImpl.copy` and
  `AttributesNSImpl.copy` are back to CPython's `self.__class__(...)`. Re-tested
  against CPython: a **subclass** now copies as itself (`MyAttrs.copy()` returns a
  `MyAttrs`), which is the property the workaround could not provide and the
  reason the row said it was not cosmetic.
- [[bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides]]
  **fixed** — the dead `return` after each abstract `raise` in
  `mimic_collections_abc.py` is removed (five of them). The `self.keys()` detour
  the row also named was already gone; the row was half a misdiagnosis, as its own
  note said.
- [[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]] **fixed** —
  every `self.__getitem__(k)` / `self.__setitem__(k, v)` in the mixins is back to
  `self[k]` / `self[k] = v`.
- [[bug-n-isinstance-does-not-accept-a-qualified-class-name]] **fixed** —
  `test/lib_mimic_collections_abc.npy` keeps its `Mapping = cabc.Mapping` rebinding
  (it has an independent reason: it is what the corpus's classes look like) but the
  comment no longer claims the qualified spelling is a compile error, and two rows
  now assert `isinstance(m, cabc.Mapping)` directly so the restored capability is
  gated rather than merely unblocked.
- `MutableMapping.update()` **stays** — see the table. Its blocker
  ([[bug-n-hasattr-through-an-untyped-parameter-is-always-false]]) is genuinely
  fixed, and reverting it uncovered a different live bug underneath, filed as
  [[bug-n-keys-through-an-untyped-receiver-is-not-dispatched-cross-module]].

`test/lib_mimic_collections_abc.npy` 49/49 and byte-identical to CPython;
`make lib-test` green.

**The lesson this batch adds to the 2026-08-17 one below.** That entry established
that a row is revertible when the **pin** carries the fix, not when the bug is
fixed. This one adds: a row is revertible when the pin carries the fix **and the
idiomatic form it unblocks actually runs**. `update()`'s stated blocker was fixed
and its stated revert still could not be made; the crash was one call deeper, in a
bug whose own ticket was closed. Reverting is a measurement, not a bookkeeping
step — run the reverted code before dropping the row.

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
