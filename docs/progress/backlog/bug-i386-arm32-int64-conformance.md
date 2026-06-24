# bug: i386/arm32 diverge on Int64 via fn-return / record-field / mixed ops

- **Type:** bug (Track A — 32-bit Int64 codegen)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-24 (exposed after the frozen-string-deref fix unmasked it)
- **Severity:** medium — blocks `make test-i386` / `make test-arm32` (the first
  wall both gates hit now is `test_conformance_2`). aarch64 is green.

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
