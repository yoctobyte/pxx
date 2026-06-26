# bug: i386/arm32 diverge on Int64 via fn-return / record-field / mixed ops

- **Type:** bug (Track A — 32-bit Int64 codegen)
- **Status:** done (2026-06-24)
- **Track:** A
- **Opened:** 2026-06-24 (exposed after the frozen-string-deref fix unmasked it)
- **Severity:** medium — blocks `make test-i386` / `make test-arm32` (the first
  wall both gates hit now is `test_conformance_2`). aarch64 is green.

## Root cause / fix

Not a `shl`/`div`/`mod`/fn-return/record bug at all — the common thread was the
explicit **`Int64(x)` numeric reinterpret of a 32-bit operand**. In `ir.inc`
(`AN_PTR_CAST`, `ASTIVal = -1`) a widening numeric cast only **re-tagged** the
inner node's `IRTk` to the 64-bit width. On 32-bit targets that tells consumers
"this is 64-bit" but no sign/zero-extend ever runs — `EmitNode64` widens only
when the SOURCE tag is narrow, and the re-tag erased the narrowness — so the high
word (`edx` / `r1`) held garbage. x86-64/aarch64 hid it because a 32-bit load is
already full-width in one register.

Fix: when the cast widens 32->64 (`castTk` is Int64/UInt64 and the inner node is
not already 64-bit), emit a real widen by adding a 64-bit `0` — the inner node
keeps its narrow tag so the extend direction follows its signedness, and the sum
carries the cast's 64-bit tag. No-op on 64-bit targets. The narrowing/same-width
re-tag (the `bug-shl-signed-integer-width` path) is unchanged. Required a 1-gen
reseed (`make bootstrap`); fixedpoint holds. All gates green:
`make test` + `test-i386` + `test-arm32` + `test-aarch64` + `cross-bootstrap` +
float-determinism + esp-bare + esp-softfloat.

## Symptom

`test_conformance_2` run on i386/arm32 diverges from the x86-64 oracle:

```
i386 : q=7000000005 mix=222669149779   fact20=5729255460435132416  rec ... sum=-2427387009277703680
x86  : q=7000000005 mix=111000000083   fact20=2432902008176640000  rec ... sum=1000000000
```

Diverging constructs (all Int64 on a 32-bit target):
- `Fact(20)` — `Fact := Int64(n) * Fact(n-1)` (recursive Int64 fn-result operand).
- `I64Mix(q,3)` — `(a shl 4) + Int64(b) - (a div 7) + (a mod 5)` (mixed Int64 shl/div/mod).
- `RecSum(r)` — `r.A + Int64(r.B)` (Int64 record field add).

## Not this

Plain Int64 multiply / add of locals is correct on i386/arm32 (verified:
`a*b`=1e12, `100000*1000000`=1e11, `20!` literal all match). So it is specific to
Int64 reached through a **function return**, a **record field**, or the
**shl/div/mod** mix — likely the edx:eax / r0:r1 pairing of those operand sources.

## Acceptance

`make test-i386` and `make test-arm32` match the x86-64 oracle on
`test_conformance_2`; existing tests stay green.

## Repro

`./compiler/pascal26 --target=i386 test/test_conformance_2.pas /tmp/c2 && tools/run_target.sh i386 /tmp/c2`
vs the x86-64 build. Narrow with `Fact`/`I64Mix`/`RecSum` in isolation.
