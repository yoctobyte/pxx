# bug: `WriteLn(real)` default format differs from FPC

- **Type:** bug (output formatting / FPC-compat) — Track A
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low (formatting parity; loud, not a silent miscompile)
- **Relation:** sibling of `bug-writeln-boolean-format`.

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
