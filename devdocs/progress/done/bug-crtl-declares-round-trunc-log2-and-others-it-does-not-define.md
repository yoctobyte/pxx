---
slug: bug-crtl-declares-round-trunc-log2-and-others-it-does-not-define
track: crtl
prio: 75
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program)
tags: [crtl, math, link, panorama]
summary: "NOT A GAP, as filed: crtl DOES define round, lround, llround, trunc, log2, log10, modf and copysign (src/math.c, all in crtl_names.inc), and a --shared-runtime object calling them links with `pxx --link`, no libc. The ticket came from a misread: the warning 'crtl does not define round, ...' appeared in the --system-libs=m row, where crtl's math.c is not used at all, and it was triggered by a static-inline experiment of mine that never landed. Checking it bit for bit against glibc found one real difference, fixed here: log10 of a negative number returned -nan where glibc returns nan. Test: c_rndlog26, the eight functions on edge values, as a crtl program and through pxx --link, against gcc+glibc."
---

# crtl's round/trunc/log2/... (filed as missing; they are not)

Filed earlier today on the strength of this warning:

```
warning: crtl does not define round, lround, llround, trunc, log2, log10, modf,
copysign — this C program will import them from the system C library at run time
```

That warning came from `csystem_libs_granular_math_b112` (`--system-libs=m`:
math is libm's, so crtl's math.c is not part of the program). The cause was a
version of feature-crtl-long-double-math-aliases that used static inline
forwards; it was replaced by macros before it landed. In crtl mode and in
`--shared-runtime` + `pxx --link` all eight resolve to crtl's own
definitions.

Measured (test/c_crtl_round_trunc_log_modf_copysign.c, bit patterns, so -0.0
and NaN signs show): identical to glibc on 0, -0, ±0.5, ±1.5, ±2.5,
0.49999999999999994, 1e15+0.5, 2^52+1, -7.75, 1e300, a subnormal, ±inf and
NaN for round/trunc/modf/copysign/lround/llround, and on powers of 2 and 10,
3, 7, extremes, 0, -1 and inf for log2/log10. The one exception was
`log10(x < 0)`: crtl gave -nan (fff8...), glibc gives nan (7ff8...). glibc's
log and log2 give -nan, and crtl already matched those. Fixed in src/math.c;
FE_INVALID is still raised.

The per-dep table this ticket carried is moot. The separate finding about
UND symbols left behind by dropped inlines stays open:
backlog-cfront/bug-c-an-unreferenced-external-stays-in-the-symbol-table-as-undefined.
