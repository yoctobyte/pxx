---
slug: feature-crtl-fpclassify-and-isnormal
track: crtl
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libinput 1.31.1 through compdb.py replay)
tags: [crtl, math]
summary: "<math.h> had no fpclassify, isnormal, FP_NAN/FP_INFINITE/FP_ZERO/FP_SUBNORMAL/FP_NORMAL or HUGE_VALF/HUGE_VALL. 75 of libinput's 91 units failed on isnormal. They are added as macros over two static inline bit tests, one per width: a float is classified as a float, because promoting it would turn a float subnormal into a normal double. The helpers call nothing, so an unused one leaves no undefined symbol. FP_* use glibc's values, so --system-libs objects agree. Test: c_fpcls26 on float and double edge values (0, -0, min, min/4, max, inf, nan), as a crtl program and a --system-libs object, against gcc."
---

# Crtl fpclassify and isnormal

isnan/isinf/isfinite stay functions of double, as before.
