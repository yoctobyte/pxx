---
prio: 45
---
# C crtl: long-double math (ldexpl, ...) missing — blocks tcc

- **Type:** bug/feature (crtl library breadth). Track B (lib/crtl), surfaced by C frontend.
- **Found:** 2026-07-07, tcc bring-up (libtcc.c:12370).

## Symptom
`call to undeclared function: ldexpl`. tcc parses its long-double float constants
via `ldexpl`/`strtold` etc. lib/crtl has `ldexp` (double) but not the `l`
(long-double) variants.

## Question first
Does pxx model `long double` distinctly, or map it to `double`? Check
ParseCDeclType for `long double`. If long double == double in pxx, the fix is a
thin alias layer: `ldexpl`->ldexp, `strtold`->strtod, `frexpl`->frexp, etc. in
lib/crtl (a header + sibling .c, C-mode). If pxx needs real 80-bit long double,
that's a much larger arc (x87 extended precision) — file separately; tcc would
then need its float constant handling checked against gcc anyway.

## Fix (assuming long double == double)
Add the `*l` long-double math aliases to lib/crtl (mirror the existing math.c
crtl shim); each just forwards to the double version. Enough to unblock tcc's
parse; correctness of tcc's emitted float constants is a later check.

## Gate
tcc libtcc.c advances past :12370; a small long-double-math test compiles/links.


## RESOLVED 2026-07-07 (Track B) — long double == double, thin aliases
Confirmed pxx maps `long double` to `double` (sizeof both 8, 3.5L round-trips).
tcc needs only `ldexpl` + `strtold`; added as double-forwarding aliases:
lib/crtl/include/math.h + src/math.c `ldexpl(x,e){return ldexp(x,e);}`;
stdlib.h + src/stdlib.c `strtold(s,e){return strtod(s,e);}`. Verified
(ldexpl(1.5,3)=12, strtold parses 2.5). lua still green. tcc advances past :12370.
