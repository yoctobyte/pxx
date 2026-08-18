# SPDX-License-Identifier: 0BSD
"""mimic_colorsys -- CPython's `colorsys`: colour-space conversion arithmetic.

Reached as `import colorsys`, which the NilPy import resolver maps to this file
and announces (`note: colorsys -> mimic_colorsys (shim, subset)`). Not named
`colorsys.py`: no file in this tree carries an upstream package name, so the
tree always says what a thing is.

WHY COMPLETE IS ACHIEVABLE HERE. Like `bisect`, this module is arithmetic and
nothing else -- six functions over floats, no platform surface, no state, no
version drift. The bodies below are CPython's Lib/colorsys.py transcribed, so
"correct" means "returns the same floats", which is exactly what
test/lib_mimic_colorsys.npy checks by running the same file both ways.

The failure mode this guards against is the one that makes a colour shim worth
testing at all: hue is circular, so an implementation with the sector arithmetic
subtly wrong still returns three floats in [0, 1] and still looks like a colour.
The test therefore walks all six 60-degree sectors rather than checking that
red comes back red.

SCOPE. `tinycss2/color3.py` imports exactly one name, `hls_to_rgb`. The HSV and
inverse conversions are here because they are the same twenty lines and a
caller reaches for them together.

DELIBERATELY ABSENT: `rgb_to_yiq` / `yiq_to_rgb`. Nothing in the corpora uses
them, and unlike the rest they are not a fixed spec -- the coefficient table
CPython ships was corrected in place at one point, so a transcription is only
right against a particular CPython. A caller who wants YIQ gets a loud
unresolved-name error instead of numbers from an unstated vintage.
"""

# Constants CPython exposes and callers occasionally read.
ONE_THIRD = 1.0 / 3.0
ONE_SIXTH = 1.0 / 6.0
TWO_THIRD = 2.0 / 3.0


def _v(m1, m2, hue):
    """The HLS sector helper. CPython calls this `_v`; it is not public API."""
    hue = hue % 1.0
    if hue < ONE_SIXTH:
        return m1 + (m2 - m1) * hue * 6.0
    if hue < 0.5:
        return m2
    if hue < TWO_THIRD:
        return m1 + (m2 - m1) * (TWO_THIRD - hue) * 6.0
    return m1


def hls_to_rgb(h, l, s):
    """Hue/lightness/saturation -> red/green/blue, all in [0, 1]."""
    if s == 0.0:
        return (l, l, l)
    if l <= 0.5:
        m2 = l * (1.0 + s)
    else:
        m2 = l + s - (l * s)
    m1 = 2.0 * l - m2
    return (_v(m1, m2, h + ONE_THIRD), _v(m1, m2, h), _v(m1, m2, h - ONE_THIRD))


def rgb_to_hls(r, g, b):
    """Red/green/blue -> hue/lightness/saturation, all in [0, 1]."""
    maxc = max(r, g, b)
    minc = min(r, g, b)
    sumc = maxc + minc
    rangec = maxc - minc
    l = sumc / 2.0
    if minc == maxc:
        return (0.0, l, 0.0)
    if l <= 0.5:
        s = rangec / sumc
    else:
        s = rangec / (2.0 - maxc - minc)
    rc = (maxc - r) / rangec
    gc = (maxc - g) / rangec
    bc = (maxc - b) / rangec
    if r == maxc:
        h = bc - gc
    elif g == maxc:
        h = 2.0 + rc - bc
    else:
        h = 4.0 + gc - rc
    h = (h / 6.0) % 1.0
    return (h, l, s)


def hsv_to_rgb(h, s, v):
    """Hue/saturation/value -> red/green/blue, all in [0, 1]."""
    if s == 0.0:
        return (v, v, v)
    i = int(h * 6.0)
    f = (h * 6.0) - i
    p = v * (1.0 - s)
    q = v * (1.0 - s * f)
    t = v * (1.0 - s * (1.0 - f))
    i = i % 6
    if i == 0:
        return (v, t, p)
    if i == 1:
        return (q, v, p)
    if i == 2:
        return (p, v, t)
    if i == 3:
        return (p, q, v)
    if i == 4:
        return (t, p, v)
    return (v, p, q)


def rgb_to_hsv(r, g, b):
    """Red/green/blue -> hue/saturation/value, all in [0, 1]."""
    maxc = max(r, g, b)
    minc = min(r, g, b)
    rangec = maxc - minc
    v = maxc
    if minc == maxc:
        return (0.0, 0.0, v)
    s = rangec / maxc
    rc = (maxc - r) / rangec
    gc = (maxc - g) / rangec
    bc = (maxc - b) / rangec
    if r == maxc:
        h = bc - gc
    elif g == maxc:
        h = 2.0 + rc - bc
    else:
        h = 4.0 + gc - rc
    h = (h / 6.0) % 1.0
    return (h, s, v)
