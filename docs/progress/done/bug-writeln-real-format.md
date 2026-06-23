# bug: `WriteLn(real)` default format differs from FPC

- **Type:** bug (output formatting / FPC-compat) — Track A
- **Status:** DONE 2026-06-23
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low (formatting parity; loud, not a silent miscompile)
- **Relation:** sibling of `bug-writeln-boolean-format`.

## Resolution (2026-06-23)

Default scientific float format now matches FPC's **Double** field width: 17
significant digits (`d.<16 digits>`) and a 3-digit exponent. The mantissa is
extracted MSD-first into a 17-digit integer (each step truncates a value in
`[0,10)`, with one guard digit rounding half-up), instead of one
`value * 10^16` double multiply that overflows the 53-bit mantissa and zeroed
the low digits. This also fixed two accuracy bugs the old path had:
`1.0e-100` printed as `0.0...E+000`, and `1.0e100` as `9.99..E+099`.

Touched all four code paths so output is byte-identical across targets:
- x86-64 `EmitWriteFloatSci` (symtab.inc)
- aarch64 `EmitWriteFloatSciA64` (ir_codegen_aarch64.inc)
- arm32 + i386 `PXXWriteFloatSci` (builtin/builtinheap.pas)

Gate: `make test` green (golden `test/test_float_write.pas` updated to 17-digit
output); self-host byte-identical. Verified x86-64/aarch64/i386/arm32 all emit
identical text under qemu.

### Residual (intentionally not chased — separate, deeper issues)

1. **Bare-literal parity is unreachable.** FPC types a bare real literal as the
   *smallest* type that holds it exactly: `writeln(1.0)` → Single
   (`1.000000000E+00`), `writeln(3.14159)` → Extended
   (`3.14158999999999999993E+0000`). pxx has only Double, so it always prints
   the Double form. Parity holds for **Double-typed** values, which is the
   meaningful target. (Per-literal type inference + Single/Extended would be a
   separate feature.)
2. **Last 1–2 digits diverge on hard values** (e.g. `1234.5` →
   `1.2345000000000002E+003`, large/small exponents). Double-arithmetic scaling
   cannot reproduce FPC's correctly-rounded last digit at 17 sig figs; that
   needs a bignum dtoa (Ryu/Grisu/Dragon). The existing code comment already
   declared this tolerance ("last 1–2 digits may differ … adequate"). Filed as
   a possible future `feature-bignum-float-dtoa` if exact parity is ever needed.

## Symptom

`writeln(3.14159)` — default (no width/precision) float formatting:

```
fpc:  3.14158999999999999993E+0000
pxx:  3.141590000000000E+000
```

Two divergences:
1. **Mantissa precision** — FPC emits ~17 significant digits (full double),
   pxx 16.
2. **Exponent width** — FPC pads the exponent to 4 digits (`E+0000`), pxx 3
   (`E+000`).

The explicit fixed form matches (`writeln(1.5:0:2)` agrees), so only the default
scientific path differs.

## Expected

Match FPC's default `Str(real)` formatting: 17 significant digits and a
4-digit exponent field, for output parity with the FPC-seeded toolchain and any
golden-output tests.

## Repro

```pascal
begin writeln(3.14159); end.
```
