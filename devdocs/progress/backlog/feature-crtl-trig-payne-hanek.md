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
