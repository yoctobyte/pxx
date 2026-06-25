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
| `lib/rtl/classes.pas` (`TStream.Read`/`Write` bodies) | self-calls qualified `Self.Read(...)` / `Self.Write(...)` | [[bug-bare-read-write-in-method-hits-intrinsic]] | bare `Read(...)` / `Write(...)` |
| `lib/rtl/bignum.pas` (`BigFromStr`, `BigDivMod`), `examples/bignum/bigmath.pas` | managed-return calls bound to a temp before being passed as an arg (no `BigAdd(BigMulSmall(x,…),…)` nesting) | [[bug-managed-record-result-self-arg]] (aka `bug-nested-managed-return-call-arg`) | nest the calls directly |
| `lib/rtl/chacha20poly1305.pas` (Poly1305) | native 5×26-bit limbs instead of `bignum` | [[bug-managed-record-result-self-arg]] — *partial:* limbs are the idiomatic choice anyway, so this is **not** a pure workaround; keep even after the fix | — (keep) |
| `lib/rtl/x25519.pas` (`Asr64`, `Sel25519`) | bitwise complement written `-x-1` / `-b` instead of `not` | [[bug-not-on-int64-is-boolean]] — `not` on an `Int64` *expression* miscompiles | plain `not` |
| `lib/rtl/aesgcm.pas` (`BlkCopy`, used in `EncryptBlk`, `GfMul`, `AesCtr`, `GcmSetup`, `GcmTag`) | whole static-array `:=` replaced by element-copy loops | [[bug-fixed-array-assignment-no-copy]] — `b := a` on a fixed array doesn't copy | plain `dst := src` |
| `test/lib_sha256.pas`, `test/lib_aesgcm.pas` (expected hex literals) | long literals kept on **one line** (no `'a' + 'b'`) | [[bug-string-literal-concat-compare-segfault]] — `x = 'a'+'b'` comparison segfaults | split literals with `+` |

### Coding-pattern landmines (no single site — avoid in new Track B code)

- **Managed-record return as a call arg.** Until
  [[bug-managed-record-result-self-arg]] is fixed, do not write
  `Result := F(Result, …)` or `g(F(x), …)` where the return type is a record with
  a managed field (dynamic array / AnsiString) — bind to a local first. Affects
  any `bignum`-heavy code (e.g. a future X25519/RSA written over `bignum` rather
  than fixed limbs).
- **`Length(ps^)` on a managed string through a pointer** returns garbage —
  [[bug-managed-length-via-pointer-deref]]. Deref into a local string first.
- **`Read := x` / `Write := x`** (own-name result of an intrinsic-named **virtual**
  method) miscompiles — [[bug-virtual-keyword-name-result]]. Use `Result := x`.
- **`not` on an `Int64` expression** (`not (x-1)`, `not Int64(5)`) miscompiles —
  [[bug-not-on-int64-is-boolean]]. Use the two's-complement identity: `~x` →
  `-x - 1`, `~(b-1)` → `-b`. `not` on a plain Int64 *variable* is fine.
- **Whole static-array assignment** `b := a` doesn't copy —
  [[bug-fixed-array-assignment-no-copy]]. Copy element by element (or a small
  `Copy` proc). Records and dynamic arrays are unaffected.
- **String-literal concat in a comparison** `x = 'a' + 'b'` segfaults —
  [[bug-string-literal-concat-compare-segfault]]. Keep the literal on one line, or
  assign the concat to a var first. (Assignment `v := 'a'+'b'` is fine.)

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
