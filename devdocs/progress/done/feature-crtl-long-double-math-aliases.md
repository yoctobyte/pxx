---
slug: feature-crtl-long-double-math-aliases
track: crtl
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libxkbcommon 1.13.1 through compdb.py replay)
tags: [crtl, math]
summary: "<math.h> had only ldexpl among the `l` functions. Added sqrtl fabsl floorl ceill roundl lroundl llroundl truncl fmodl powl expl logl log2l log10l frexpl modfl sinl cosl tanl atanl atan2l copysignl as function-like macros naming the double ones (long double is double in pxx). Not externs, so under --system-libs they do not bind glibc's 80-bit versions, whose x87 ABI is not pxx's; not static inline, because pxx emits an unused inline body and every <math.h> user then referenced round/llround/... (the gate's csystem_libs_granular_math_b112 caught a libc import). libxkbcommon's bench.c: llroundl(sqrtl(...)). Test: c_xkbpp26, checked also as a --system-libs object linked with glibc."
---

# Crtl long double math aliases

Still open: crtl DECLARES round, lround, llround, trunc, log2, log10, modf and copysign but
does not define them, so roundl/llroundl/... (like round itself) import the host libc at
run time and are unresolved in a gcc-free `pxx --link`. libxkbcommon's bench.c uses llroundl.

Also open: ldexpl stays an extern in src/math.c, so under --system-libs it binds glibc's
ldexpl with the wrong ABI. It wants the same inline treatment once src/math.c's body goes.
