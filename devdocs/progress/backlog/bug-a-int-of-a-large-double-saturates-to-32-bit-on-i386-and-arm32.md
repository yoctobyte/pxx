---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`Int(x)` — the builtin that returns the integral part as a FLOAT — routes through a 32-bit conversion on i386 and arm32, so any |x| >= 2^31 comes back as the saturated integer: Int(8796093022208.5) is -2147483648.0 on i386 and 2147483647.0 on arm32, against the correct 8796093022208.0. `Trunc` of the same value is right on both, and riscv32 (also 32-bit) is right, so this is those two backends, not a word-size limit. Silent wrong value in a builtin with no diagnostic."
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
