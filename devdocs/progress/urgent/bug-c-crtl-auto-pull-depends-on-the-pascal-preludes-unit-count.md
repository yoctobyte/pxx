---
track: C
prio: 75
type: bug
blocked-by: []
---

# crtl's auto-pull silently no-ops when pxxcio's `uses` clause has two units

- **Type:** bug (silent unresolved link → SIGSEGV) — **Track C** (`cpreproc.inc`)
- **Found:** 2026-08-10, while splitting C's math off the Pascal RTL
  ([[bug-c-pascal-math-names-hijack-libc-through-pxxcio]]). It **blocks** that
  work completely.

## The reproduction — one word, and it is not the word you expect

`lib/rtl/pxxcio.pas` is auto-pulled into every C program. Vary only its `uses`
clause, compile `test/crtl_inttypes.c`, run:

| `uses` clause in pxxcio | result |
| --- | --- |
| `platform, builtinheap, math` (today) | exit 42 ✓ |
| `platform, builtinheap` | **SIGSEGV** |
| `platform, builtinheap, math_ext` | exit 42 ✓ |
| `platform, math, builtinheap` | exit 42 ✓ |

**Any third unit works. Two units fail.** It has nothing to do with `math` —
that is simply the unit that happens to be third today, which is why this has
never been seen.

## What actually breaks

With two units, the C preprocessor's crtl auto-pull does not fire at all:

```
$ pascal26 --debug ... crtl_inttypes.c | grep auto-pull
  (three units)   auto-pull crtl impl lib/crtl/src/stdlib.c
                  auto-pull crtl impl lib/crtl/src/string.c
  (two units)     (nothing)
```

so every function those files define is declared and never emitted —
`--debug` shows `proc 355: imaxdiv at -1`, `strtoimax at -1`, … — and the call
site jumps to garbage. In `crtl_inttypes` the crash is a `rep movsb` with a null
source: the struct-returning `imaxdiv` "returned" an unmapped hidden-destination
pointer.

**No diagnostic at any point.** The compile prints `ok:`.

## Where to look

`CPAutoPullCrtlImpl` (cpreproc.inc:2120) reuses the just-processed header's
include DEPTH SLOT for the impl — the `CPrepInclude0..N` globals — and then:

```pascal
CPLoadInclude(depth);
if CPIncludeLength(depth) = 0 then Exit;   { no sibling impl — pure-header module }
```

That `Exit` treats "the slot came back empty" as "this module is header-only",
so a slot that is empty for ANY OTHER REASON is silently indistinguishable from
a module with no `.c`. That is the line that turns the fault into silence, and
it should be the first thing fixed regardless of the root cause: a failed load
of a file that EXISTS must be an error, not a shrug.

Why the unit count moves it is the part still to find — the Pascal prelude's
units and the C include slots should not share an index, and apparently they do.

## Why it is filed urgent

1. It blocks the math split, which is itself fixing a live silent-wrong-answer
   family (`pow(2,10) = 1`) and an open `test-core` red.
2. On its own it is a silent unresolved-symbol link — the same class as
   `bug-a-libcfree-unresolved-extern-silent-zero`, which got its own diagnostic
   for exactly this reason.

## The blocked work, verified and banked

The math split itself is DONE and measured — it is only this bug that stops it
landing. With `uses math` removed and the four functions below added to
`lib/crtl/src/math.c`, the entire libm surface (sin cos tan asin acos atan
atan2 exp log log10 log2 pow sinh cosh tanh sqrt cbrt hypot floor ceil fmod
fabs copysign trunc round rint isnan isinf frexp ldexp modf) is **byte-identical
to gcc**, `isnan(5.5)` stops answering TRUE, and `--system-libs=c` stops linking
libm (the b113 red goes green).

The two halves are NOT separable: adding the four while `uses math` remains
makes things worse (two competing definitions — asin/acos/atan2 start returning
NaN). Land them together, after this bug.

**Update, same night:** `floor` and `ceil` landed independently in `11019fe12`
("give floor/ceil real bodies — my Floor/Ceil change pulled in libm"), which
also cleared the b113 red. So only **`sqrt` and `fmod`** remain to add, plus the
`uses math` removal. The two banked below are unchanged and still needed; the
floor/ceil pair below is superseded by what is already in the tree (their
version handles the observable -0.0 the same way, found by the same gcc
differential).

The verified implementation is saved as a patch on this ticket rather than in
the tree:

```c
#define CRTL_2P52 4503599627370496.0

double floor(double x) {
  double t;
  if (!(fabs(x) < CRTL_2P52)) return x;      /* |x|>=2^52, inf, NaN: integral */
  t = (double)(long long)x;
  if (t > x) t -= 1.0;
  return t == 0.0 ? copysign(0.0, x) : t;    /* floor(-0.0) is -0.0 */
}

double ceil(double x) {
  double t;
  if (!(fabs(x) < CRTL_2P52)) return x;
  t = (double)(long long)x;
  if (t < x) t += 1.0;
  return t == 0.0 ? copysign(0.0, x) : t;    /* C99: ceil(-0.5) is -0.0 */
}

/* exact truncated remainder: scale |y| under |x| by powers of two and
   subtract — every step is exact (Sterbenz), so no rounding however large x/y */
double fmod(double x, double y) {
  double ax, ay, s; int ex, ey;
  if (isnan(x) || isnan(y) || isinf(x) || y == 0.0) { s = 0.0; return s / s; }
  if (isinf(y)) return x;
  ax = fabs(x); ay = fabs(y);
  if (ax < ay) return x;
  frexp(ax, &ex); frexp(ay, &ey);
  s = ldexp(ay, ex - ey);
  if (s > ax) s = ldexp(s, -1);
  while (s >= ay) { if (ax >= s) ax -= s; s = ldexp(s, -1); }
  return copysign(ax, x);
}

/* Newton + one correctly-rounded correction from an exact residual — ported
   from lib/rtl/math.pas's Sqrt, deliberately identical: this is the one of the
   four both languages want bit-for-bit. */
double sqrt(double x) {
  double g, ng, z, gh, gl, c, p, e, r;
  unsigned long long bits; int i;
  if (x < 0.0) { z = 0.0; return z / z; }
  if (x == 0.0) return x;                    /* keeps -0.0 */
  if (isnan(x) || isinf(x)) return x;
  bits = *(unsigned long long *)&x;
  bits = (bits >> 1) + (1023ULL << 51);      /* halve the exponent field */
  g = *(double *)&bits;
  for (i = 0; i < 8; i++) { ng = 0.5 * (g + x / g); if (ng == g) break; g = ng; }
  p = g * g;
  if ((p - p) != 0.0) return g;              /* g*g overflowed near DBL_MAX */
  c = g * 134217729.0;                       /* Dekker split, 2^27+1 */
  gh = c - (c - g); gl = g - gh;
  e = ((gh * gh - p) + 2.0 * gh * gl) + gl * gl;
  r = (x - p) - e;
  return g + r / (2.0 * g);
}
```

plus `lib/rtl/pxxcio.pas`: `uses platform, builtinheap, math;` →
`uses platform, builtinheap;`.

Gate for the combined change: `make lib-test`, the gcc differential above, and
b113 linking libc only.
