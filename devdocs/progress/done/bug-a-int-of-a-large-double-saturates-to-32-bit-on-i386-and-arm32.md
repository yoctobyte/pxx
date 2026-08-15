---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`Int(x)` — the builtin that returns the integral part as a FLOAT — routes through a 32-bit conversion on i386 and arm32, so any |x| >= 2^31 comes back as the saturated integer: Int(8796093022208.5) is -2147483648.0 on i386 and 2147483647.0 on arm32, against the correct 8796093022208.0. `Trunc` of the same value is right on both, and riscv32 (also 32-bit) is right, so this is those two backends, not a word-size limit. Silent wrong value in a builtin with no diagnostic."
status: done
owner: claude-A-N
---

# `Int()` of a large Double saturates to 32 bits on i386 and arm32

- **Type:** bug (silent wrong value, compiler builtin) — **Track A**
  (`compiler/**`; `Int` lowers in the builtin/codegen layer, not in `lib/**`).
- Filed by Track B on 2026-08-15 after it turned `Sin(1e20)` into `NaN` on
  i386 and arm32 while `lib_math_correctly_rounded` was green on x86-64,
  aarch64 and riscv32
  ([[bug-b-rtl-math-transcendentals-lose-argument-reduction]]).

## Repro

```pascal
program intprobe;
var v: Double;
begin
  v := Int(8796093022208.5);        { 2^43 + 0.5 }
  writeln(v:0:2, ' ', Trunc(8796093022208.5));
end.
```

| target | `Int(2^43 + 0.5)` | `Trunc(...)` |
| --- | --- | --- |
| x86-64 | `8796093022208.00` | 8796093022208 |
| aarch64 | `8796093022208.00` | 8796093022208 |
| riscv32 | `8796093022208.00` | 8796093022208 |
| **i386** | **`-2147483648.00`** | 8796093022208 |
| **arm32** | **`2147483647.00`** | 8796093022208 |

Same for 2^41 and for 2^52-0.5, and for the negative (`Int(-2^43-0.5)` is
`-2147483648.00` on i386). The threshold is 2^31, and the two wrong values are
the two 32-bit saturation constants, which is the signature: the double is
being converted to a 32-bit integer and back rather than having its fraction
removed.

**`Trunc` is correct on every target**, and riscv32 — also 32-bit — is correct
too, so this is not a word-size limitation. It is those two backends' lowering
of this one builtin.

## Why it matters more than it looks

`Int` is *the* float-domain "remove the fraction" primitive: it takes a Double
and returns a Double, so its whole reason to exist is the range where the value
does not fit an integer. Restricting it to 2^31 removes the case it is for. And
it does so silently — no diagnostic, no trap, just a plausible number.

It is already load-bearing in the RTL: `lib/rtl/math.pas`'s `DdRint` uses
`Int()` under a `>= 2^52` guard (safe today only because its callers stay under
2^31), and the trig argument reduction hits it at ~2^43 for large arguments,
where it turned `Sin(1e20)` into NaN on exactly the two affected targets.

## Expected

`Int(x)` = truncate toward zero in the FLOAT domain, for every finite double,
on every target. `|x| >= 2^52` is already integral and must be returned
unchanged. No 32-bit integer may appear anywhere in the lowering.

## Sweep before closing

- `Int` with values at 2^31, 2^43, 2^52, 2^63 and above, both signs, plus
  infinities and NaN (which must pass through).
- `Frac`, which is `x - Int(x)` and inherits any error — check it on the same
  values.
- `Round` and `Trunc` on the same targets for the same range, in case the 32-bit
  path is shared.
- The other 32-bit backend, riscv32, is *correct* — its lowering is the model to
  copy.

## Gate

The table above matches on all five targets, `make test` + self-host
fixedpoint, and a cross run of the new cases. Track B's `lib_math_correctly_rounded`
already covers the downstream symptom once this lands — it is green on
x86-64/aarch64/riscv32 and, with the RTL's local avoidance removed, would go
green on i386/arm32 too.

## RESOLVED — and the ticket's "correct" column was only correct in the range it tested

The table stops at 2^43. That is above i386/arm32's 2^31 ceiling and below
x86-64/aarch64's, so it read the two 64-bit targets as the oracle when they had
the SAME bug one power of two higher. Fixing i386 and arm32 first is what
exposed it: three 32-bit targets then agreed with each other and disagreed with
x86-64, and FPC — run as the actual oracle rather than assumed — sided with the
three.

| | `Int(2^43+0.5)` | `Int(2^63)` | `Int(1e20)` | `Int(+Inf)` | `Frac(1e20)` |
| --- | --- | --- | --- | --- | --- |
| FPC (oracle) | 8796093022208 | 9223372036854775808 | 1e20 | `+Inf` | 0 |
| x86-64 before | ok | **-9223372036854775808** | **-9223372036854775808** | **-9.22e18** | **1.09e20** |
| aarch64 before | ok | ok | **9223372036854775808** | **9.22e18** | **9.08e19** |
| i386 before | **-2147483648** | wrong | wrong | wrong | wrong |
| arm32 before | **2147483647** | wrong | wrong | wrong | wrong |
| riscv32 / xtensa | ok | ok | ok | ok | ok |

**One concept, five lowerings, four wrong.** `Int` is float→float; every backend
except the two that call the softfloat kernel routed it through an integer
register and inherited that register's range as a silent ceiling. The fix is the
same rule everywhere — remove the fraction *without leaving the float domain*:

- **i386** (`ir_codegen386.inc`, new `EmitTruncToIntegral386`): x87 `frndint`
  with the control word's RC set to truncate and restored after. No SSE
  round-to-integral exists below SSE4.1, and the x87 register is wider than a
  double, so the load/store are exact.
- **x86-64** (`ir_codegen.inc`, new `EmitTruncToIntegralX64`): the value is
  already carried as double BITS in rax, so this is pure bit manipulation —
  clear the fractional mantissa bits selected by the exponent, the same rule
  `__pxx_dint` implements.
- **aarch64**: `frintz d0, d0` — ARMv8 baseline, exactly this operation.
- **arm32**: VFPv2/v3 has no round-to-integral (`vrintz` is ARMv8), so it calls
  `__pxx_dint` / `__pxx_dfrac` like riscv32 and xtensa, keeping the old VFP path
  as a fallback for a minimal program that never linked softfloat.
- **riscv32 / xtensa**: unchanged; they were the model.

`Frac` was rewritten as `x - Int(x)` on each of the four, so it inherits the fix
rather than the bug.

**Verified.** All five targets now produce byte-identical output for
`Int`/`Frac`/`Trunc`/`Round` over 2^31, 2^42, 2^43, 2^52, 2^53, 2^63, 1e20,
1e300, both signs, ±0.5, ±0, ±Inf and NaN — and those rows match FPC exactly,
including the signed zero FPC prints for `Int(-0.5)`. `Frac(+Inf)` = NaN is the
masked-IEEE answer; FPC traps there (RTE 208), which is the already-decided
divergence recorded in the test header, not a new one. `Single`-typed `Int`/
`Frac` match FPC on all five too. `lib_math_fast_tolerance` prints `MATHFAST OK`
on i386 and arm32. `lib_math_correctly_rounded` goes from `Sin(1e20) = NaN` to
the SAME 4 one-ulp failures x86-64 and `pinned` already have — pre-existing
Track B ULP work, not this bug. xtensa's compile failure on the probe is
pre-existing (identical on `pinned`). `tools/gate.sh quick` GREEN.

Regression rows added to `test/test_cross_trunc_round_saturate.pas` — the same
family (float→integral at the range boundary), already wired as an
x86-64-oracle differential on all four cross targets, and its native assertion
pins only `head -5`, so the Trunc/Round contract it records is untouched.

**Follow-up for Track B (not done here — `lib/**` is not Track A's lane):**
`devdocs/dev/track-b-workarounds.md` line 19 records `lib/rtl/math.pas`'s
`DdFloor`/`DdRint` spelling `Double(Trunc(x))` to dodge this bug. `Int(x)` is
now correct on every target, so that workaround can be reverted per its
revert-when-fixed lifecycle.

## Log
- 2026-08-15 — resolved, commit 5b6e1728d.
