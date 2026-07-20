---
track: B
prio: 15
type: feature
---

# crtl libm: Payne-Hanek reduction for |x| >= 1e8 trig (sin/cos/tan)

- **Track:** B (lib/crtl/src/math.c). Tag: compat.
- **Opened:** 2026-07-19, split out of
  feature-crtl-libm-correctly-rounded-transcendentals (b385).

crtl's correctly-rounded sin/cos/tan use Cody-Waite pi/2 reduction (three
24-bit chunks + dd tail), valid for |x| < 1e8; beyond that they fall back to
the Pascal Sin/Cos/Tan (1-ulp class, and badly wrong for astronomically large
args). JS exposes the full double range (Math.sin(1e300) is a one-liner), so
the surface isn't fully correct until huge arguments reduce properly.

Shape: fdlibm-style __kernel_rem_pio2 — x split into 24-bit chunks, 2/pi as
a table of 24-bit chunks in doubles (~50 entries for 1200 bits), exact
double convolution + carry propagation, fraction times pi/2 into the existing
dd kernels. No int128 needed (24x24 products are exact in double). Wire into
crtl_trig_reduce's |x| >= 1e8 branch, extend the b385 sweep with a
huge-magnitude band, judge vs 130-digit references (glibc will occasionally
lose — that's expected, see decide-crtl-libm-glibc-bit-parity).

## LANDED 2026-07-20 (Track B)

`crtl_trig_reduce_big` in `lib/crtl/src/math.c`; `__crtl_sin` / `__crtl_cos` /
`__crtl_tan` now reduce properly past 1e8 instead of falling back to the Pascal
routines. The `extern Sin/Cos/Tan` fallback declarations are gone.

**Correction to my own earlier note on this ticket.** I first stopped here and
recorded that verification was blocked because the host has no `mpmath`. That
was wrong. Python's `stdlib` `Decimal` does the job: pi via Machin arctan at 400
digits, the argument reduced mod 2pi at full precision (with `Emax` raised so
1e308 does not overflow the context), then a Taylor series. The blocker I cited
did not exist, and the reduction is exactly the kind of code that should not be
left unverified on a bad excuse.

**Results — all correctly rounded, 0 ulp:**
- 36 hand-picked cases (1e8, 1e12, 1e16, 1e20, 1e100, 1e300, 2e300, DBL_MAX,
  2^53, a negative, and the 1e8 boundary) across sin/cos/tan.
- A 200-value random sweep, log-uniform over [1e8, 1e308], both signs, judged
  the same way: 600 results, **zero** above 0 ulp on any of the three.

**Implementation notes worth keeping:**
- The 2/pi table is 60 chunks of 24 bits (1440 bits). 24 is not arbitrary — a
  24x24 product is below 2^48 and therefore exact in a double, which is what
  lets the whole convolution run in plain double arithmetic with no int128 and
  no error compensation.
- Only terms whose exponent is >= 2 are skipped as multiples of 4, so the work
  is constant no matter how enormous x is.
- The `mod 4` fold per term is exact: `t` carries 50 significant bits, and
  whenever `t >= 4` the residue needs at most 2 integer bits plus t's fractional
  bits, which stays inside 53. Below that threshold no reduction is needed.
- Table leading entries cross-check against fdlibm's published `ipio2`
  (0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1), so the derivation is verified
  against an independent source rather than only against itself.

**Gated:** `test/crtl_trig_huge.c` in `make lib-test`, exit 42. It compares raw
bit patterns and uses no `printf` — printf's float path is part of what such a
test would otherwise be testing *with*, and it is separately unusable under the
current pin (undefined `__pxx_fegetround`).

The existing b385 sweep still compiles; it runs under `make test` with a freshly
built compiler, since it uses `printf`.


## Log
- 2026-07-20 — resolved, commit HEAD.
