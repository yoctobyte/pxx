---
prio: 35
---

# Str builtin: variable width/precision expressions (`Str(x:len:dec, s)`)

- **Type:** gap (Pascal frontend) — Track P
- **Status:** working
  ([[feature-pascal-complex-numbers-ucomplex]])
- **Owner:** opus-fruit

## Gap

`Str(x:8:3, s)` works with literal widths; with VARIABLE width/precision
(`Str(z.im:len:dec, istr)`, FPC-legal, used verbatim in FPC rtl-extra
ucomplex `cstr`) pxx errors:

```
error: Str: expected integer width after :
```

Same likely applies to `write/writeln(x:w:d)` with variable w/d — check both
while fixing. FPC evaluates the width/precision as ordinary integer
expressions.

## Workaround in the wild

`lib/rtl/ucomplex.pas` carries a hand-rolled `FmtFixed(v, len, dec)` for its
`cstr(z, len, dec)`; drop it for real `Str(x:len:dec, s)` when this lands.

## Gate

`make test` + self-host fixedpoint. Tests: Str and writeln with variable
width and precision, negative width behavior matching FPC.
