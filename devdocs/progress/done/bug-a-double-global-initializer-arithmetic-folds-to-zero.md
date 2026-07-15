---
summary: "any compile-time ARITHMETIC in a double global/static initializer folds to 0.0 (1.0/4.0, 2.0*3.0, 1024.0-0.5 all become 0.0); a bare literal is fine — silent, hits real C code"
type: bug
track: A
prio: 65
---

# double global/static initializer with arithmetic folds to 0.0

- **Type:** bug (constant folding / static-data emission for `double`). **Silent** —
  the global is just zero, no error, no warning.
- **Track:** A (compile-time constant folding of double arithmetic in a static
  initializer). Observed via the C frontend; a bare-literal init works, so it is the
  *folding of the operation*, not double statics in general. May be shared with other
  frontends — verify at fix time.
- **Found by:** the gcc c-torture harvest (`float-floor.c`), 2026-07-15,
  [[feature-t-gcc-torture-runner]]. It was almost missed — the initial triage dropped
  it because the gcc oracle also "failed" (a `-lm` link artifact at -O0), which is
  exactly why Track T no longer auto-dismisses gcc disagreement.

## Symptom

```c
extern int printf(const char*, ...);
double a = 0.5;              /* pxx: 0.5      (bare literal OK)  */
double b = 1.0/4.0;         /* pxx: 0.0      should be 0.25     */
double c = 1024.0 - 0.5;    /* pxx: 0.0      should be 1023.5   */
double f = 2.0 * 3.0;       /* pxx: 0.0      should be 6.0      */
int main(void){ printf("%.6f %.6f %.6f %.6f\n", a, b, c, f); return 0; }
```

pxx prints `0.500000 0.000000 0.000000 0.000000`; gcc prints
`0.500000 0.250000 1023.500000 6.000000`. **Any** binary op (`+ - * /`) on double
constants in a global/static initializer folds to `0.0`; only a bare literal survives.

The same expression evaluated at **runtime** (`e = 1024.0 - 1.0/32768.0;` in a
function body) is correct — so the defect is specifically the compile-time evaluation
of the *static initializer*, not double arithmetic in general.

## Impact

Real C code is full of `double k = 1.0/3.0;`, `double half_pi = 3.14159/2.0;`,
`static const double scale = 100.0/255.0;`. Every one silently becomes 0.0 — a
divide-by-scale turns into divide-by-zero or a constant-0 term, wrong results
everywhere, no diagnostic. High blast radius for a numeric C program.

## Reproduce

```
compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src library_candidates/gcc-torture/execute/float-floor.c /tmp/x && /tmp/x   # exit 134 (abort)
```
or the 5-line snippet above.

## Likely area

Static-initializer constant evaluation: the double const-expr folder probably returns
0 (integer-path evaluation of a float expression, or the static-data emitter writing
the wrong 8 bytes) for anything past a leaf literal. Check the C initializer
const-eval path first; then whether the shared double const-folder is at fault.

## Acceptance

The snippet prints the gcc values under pxx at every `-O` level; `float-floor.c`
exits 0; a `test/` regression pins double static-initializer arithmetic; confirm
whether the Pascal/other frontends share the folder and fix once if so.

## Log
- 2026-07-15 — resolved, commit PENDING.
