# bug: `WriteLn(real:w:d)` ignores the field width

- **Type:** bug (Track A — output formatting / FPC-parity)
- **Status:** DONE 2026-06-23 (x86-64; cross targets documented below)
- **Found:** 2026-06-23, differential sweep vs FPC
- **Severity:** medium (breaks aligned numeric columns/tables)

## Symptom

```pascal
writeln(3.14159:8:3);   { fpc: '   3.142'   pxx: '3.142' }
```

Fixed-format float output applied the decimals (`:d`) but dropped the field
width (`:w`): `EmitWriteFloatFixed` took only `decimals`, so the value was never
right-justified / space-padded. Integer `:w` width already worked.

## Resolution (2026-06-23)

`EmitWriteFloatFixed(width, decimals)` now runs a length pre-pass that does not
disturb xmm0: it rounds `|value| * 10^decimals`, derives the integer part and
counts its digits, adds the sign and `decimals+1` (for `.frac`), and emits
`width - len` leading spaces via the shared spaces blob — exactly FPC's
right-justification. Counting the rounded integer part means a carry that adds a
digit (e.g. `9.999:7:2` -> `  10.00`) is padded correctly; an over-width value is
not truncated; `:0:d` (width 0) is unchanged. Call site passes the `wid` that was
already parsed into the IR_WRITE node. (symtab.inc; ir_codegen.inc:2663.)

Self-host byte-identical; `make test` green. Regression:
`test/test_float_width.pas` (padding, negatives, rounding-carry, over-width,
width-0, decimals-0). Verified vs FPC.

### Cross targets (deferred)

Fixed on x86-64 (`EmitWriteFloatFixed`). aarch64 (`EmitWriteFloatFixedA64`) and
the arm32/i386 paths still ignore the width; the same length-prepass + pad needs
porting there. No regression (they behaved this way before). The default target
is fixed.
