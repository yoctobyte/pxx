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

## Track B attempt 2026-07-20 — STOPPED DELIBERATELY, with groundwork

Started this, then stopped before writing the reduction. The reason is worth
recording so the next person does not read the gap as "nobody got to it".

This lands inside a **correctly-rounded** libm. A Payne-Hanek reduction that is
subtly wrong does not fail loudly — it returns a plausible double for
`sin(1e300)` that is wrong in the last handful of bits, which is precisely the
property the surrounding code exists to guarantee. Shipping an unverified one
would be worse than the current honest fallback to Pascal `Sin`, which is
documented as 1-ulp-class and known-bad for astronomically large arguments.

Verifying it properly needs 130-digit references for the huge-magnitude band,
and this host has no `mpmath`. Judging by eye against glibc is not sufficient —
`decide-crtl-libm-glibc-bit-parity` already records that glibc itself loses in
this range, so glibc cannot be the oracle here.

**Groundwork done and verified, so it does not need redoing:**

The 2/pi chunk table, 60 chunks of 24 bits = 1440 bits, derived with a Machin
arctan computation at 700 decimal digits. First six values:

```
10680707, 7228996, 1387004, 2578385, 16069853, 12639074
```

The leading entries match fdlibm's published `ipio2` (0xA2F983, 0x6E4E44,
0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62), which is the check that the derivation
is right rather than merely self-consistent. 1440 bits covers the worst case for
double (the argument-reduction hard cases near multiples of pi/2 need ~1200).

**The shape of the remaining work**, worked out but not written:
- Split `|x|` into three 24-bit integer chunks `tx[0..2]` with `e0 = ilogb(x)-23`,
  so `|x| = (tx[0]*B^2 + tx[1]*B + tx[2]) * 2^(e0-48)`, `B = 2^24`.
- The products `tx[j]*ip[i]` are each below 2^48 and therefore **exact in a
  double** — that is the whole reason for 24-bit chunking, and it is why no
  int128 is needed. Accumulate by `k = i+j` into base-2^24 digits.
- Only the digits straddling the binary point matter: two above it for `q mod 4`,
  and enough below for a dd fraction to feed the existing kernels.
- Then `fraction * pi/2` into `crtl_sin_kernel`/`crtl_cos_kernel` unchanged, and
  wire it into `crtl_trig_reduce`'s `|x| >= 1e8` branch (currently
  `__crtl_sin`/`cos`/`tan` each early-return to the Pascal fallback).

**Prerequisite for accepting it:** a huge-magnitude band in the b385 sweep judged
against independent high-precision references — not against glibc. Getting those
references is the actual first task, not the reduction.

