---
track: B
prio: 60
type: bug
---

# `math.h`'s `M_*` constants were absent, so `M_PI` silently evaluated to 0

- **Type:** bug (crtl, silent wrong value) — **Track B** (`lib/crtl/include/math.h`)
- **Found:** 2026-08-02, while assessing [[feature-lib-pxxpdf-reportlab-compat]].
- **Resolved:** same day, commit 6ade7cabd.

## Measured

`lib/crtl/include/math.h` declared the math *functions* but defined **none** of
the `M_*` constants — no `M_PI`, no `M_E`, no `M_SQRT2`. An undeclared
identifier used as a value is treated as `0`, so this was not a compile error
but a silent wrong value:

```
$ pxx m.c && ./m           $ gcc m.c -lm && ./a.out
M_PI=0.000000              M_PI=3.141593
M_SQRT2=0.000000           M_SQRT2=1.414214
M_E=0.000000               M_E=2.718282
```

## Why it mattered

Vendored pdfgen (`lib/vendor/pdfgen/pdfgen.c:3508`) draws a circle as four
Bezier arcs with control offset `(4/3)*(M_SQRT2-1)*r`:

| | offset for r = 100 |
| --- | --- |
| correct | `+55.228475` |
| with `M_SQRT2` = 0 | `-133.333333` |

Wrong in **sign and magnitude**, so every circle pdfgen drew was garbage —
while the PDF around it stayed structurally valid and opened fine. Exactly the
shape this repo's debugging note warns about: not a crash, a plausible wrong
value far from the cause. Anything else reaching for `M_PI` (which is most
real-world C doing geometry) was silently zeroed the same way.

The compiler's own diagnostic already knew about the hazard — the
host-header warning text names `M_SQRT2` as an example of what can "silently
misbehave" — but nothing defined the constants.

## Fix

Added the full glibc set to `lib/crtl/include/math.h`: `M_E`, `M_LOG2E`,
`M_LOG10E`, `M_LN2`, `M_LN10`, `M_PI`, `M_PI_2`, `M_PI_4`, `M_1_PI`, `M_2_PI`,
`M_2_SQRTPI`, `M_SQRT2`, `M_SQRT1_2`, with glibc's exact 20+ digit spellings.

**Defined unconditionally**, not behind `_XOPEN_SOURCE` / `_USE_MATH_DEFINES`
the way glibc gates them. Real-world C reaches for `M_PI` constantly and often
without setting any feature-test macro, and compiling real code as-is is the
point; code that *does* set the macro is unaffected either way.

## Verified

- All 13 constants **bit-identical to gcc** at 17 significant digits. This pins
  the values, not just the presence of the macros, so a mis-decoded 21-digit
  literal fails too (it also incidentally confirms the C frontend decodes those
  literals correctly).
- **Cross-target**: identical output on **i386, aarch64 and arm32** as well as
  x86-64. `gate.sh lib` is x86-64 only while `lib/crtl` builds for every target,
  so this check is not optional here — see [[frank2-crtl-changes-need-cross-check]].
- End to end: a pxx-compiled `canvas.circle(100, 100, 50)` now emits control
  points at ±27.61 from the axis points, i.e. `0.5523 * r`, matching
  `(4/3)(sqrt(2)-1)`.

Test: `test/cmath_constants.c` (exit-code style, gcc-verified bit patterns,
including the pdfgen circle-offset expression itself).
