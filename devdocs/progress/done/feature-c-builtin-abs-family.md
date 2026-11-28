---
slug: feature-c-builtin-abs-family
track: C
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1: first error of 200 libsystemd/libudev units)
tags: [cfront, builtins, systemd]
summary: "__builtin_abs, __builtin_labs, __builtin_llabs and __builtin_imaxabs were unknown. systemd's ABS() (src/fundamental/macro-fundamental.h) is __builtin_imaxabs under gcc and __builtin_llabs under clang. They now join the library builtins: cparser renames them to the crtl function, and cpreproc's CAddLibBuiltinDecls puts the standard prototype on line 1 of a unit that mentions one, so no header is needed (imaxabs is spelled long long, crtl's intmax_t, so a later <inttypes.h> agrees). Test c_babs26: with no header and with both headers, against gcc."
---

# __builtin_abs family
