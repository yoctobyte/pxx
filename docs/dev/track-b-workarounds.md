# Track B — active workarounds awaiting a compiler fix

Registry of places where `lib/rtl` / `examples` code is written **non-idiomatically
to dodge an open Track A compiler bug**. When the listed bug moves to
`docs/progress/done/`, revert the workaround here and drop the entry.

Re-check each session against the latest pin (`stable_linux_amd64/default/pinned`):
the bugs get fixed fast. Verify the bug ticket is still in `backlog/`/`blocked/`
before assuming the workaround is still needed.

> Scope: only workarounds whose blocking bug is **still open**. Workarounds for
> already-fixed bugs (now in `done/`) are a separate cleanup pass — see the
> bottom section.

## Waiting on an open bug

| Where | Workaround | Blocking bug (open) | Revert to |
|---|---|---|---|
| `lib/rtl/bignum.pas` (`BigFromStr`, `BigDivMod`), `examples/bignum/bigmath.pas` | managed-return calls bound to a temp before being passed as an arg (no `BigAdd(BigMulSmall(x,…),…)` nesting) | [[bug-managed-record-result-self-arg]] (aka `bug-nested-managed-return-call-arg`) | nest the calls directly |
| `lib/rtl/chacha20poly1305.pas` (Poly1305) | native 5×26-bit limbs instead of `bignum` | [[bug-managed-record-result-self-arg]] — *partial:* limbs are the idiomatic choice anyway, so this is **not** a pure workaround; keep even after the fix | — (keep) |
| `lib/rtl/aesgcm.pas` (`BlkCopy`, used in `EncryptBlk`, `GfMul`, `AesCtr`, `GcmSetup`, `GcmTag`) | whole static-array `:=` replaced by element-copy loops | [[bug-fixed-array-assignment-no-copy]] — **fixed generally (v72)**, but a full revert of *this unit* still segfaults at the GCM path (residual, NOT minimally reproducible — every isolated `array :=` pattern passes on v72). **Keep `BlkCopy` here** until the residual is understood. | (do not revert yet) |
| `lib/rtl/ed25519.pas` (EC points) | a point's 4 field coords are **4 separate standalone TGf vars**, never an `array of TGf` or a record of TGf | [[bug-aggregate-member-array-as-var-param]] — passing an aggregate-member array by ref segfaults | a `TPoint = array[0..3] of TGf` / record |

### Coding-pattern landmines (no single site — avoid in new Track B code)

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
