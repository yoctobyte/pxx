---
slug: bug-crtl-declares-round-trunc-log2-and-others-it-does-not-define
track: crtl
prio: 75
type: bug
status: backlog
owner: unassigned
created: 2026-11-28
found-by: pxx2 (Panorama all-pxx program; pixx-cc asked for it as an open ticket)
tags: [crtl, math, link, panorama]
summary: "lib/crtl/include/math.h declares round, lround, llround, trunc, log2, log10, modf and copysign, but lib/crtl/src defines none of them. A crtl program that calls one gets a warning and imports it from the host libc at run time. A --shared-runtime object leaves it undefined, so a libc-free `pxx --link` cannot resolve it. This blocks the all-pxx Panorama link: wayland's wl_fixed_from_double calls round. Wanted: real definitions in src/math.c (and the f variants where they are declared), each checked against glibc."
---

# crtl declares math functions it does not define

The compiler's own warning names the set:

```
warning: crtl does not define round, lround, llround, trunc, log2, log10, modf,
copysign — this C program will import them from the system C library at run time
```

## Dependencies that reference them (update as they land)

Measured as undefined symbols in the `--shared-runtime --threadsafe` replay
objects (`nm -u`):

| dep | symbols | where |
|---|---|---|
| zlib 1.3.1, expat 2.7.4, libffi 3.5.2, pixman 0.46.4, freetype 2.14.2 | none | |
| wayland 1.24.0 | round (UND only) | `wl_fixed_from_double` in wayland-util.h, a static inline: the body is dropped and there is no relocation, but the UND symbol stays in all 11 objects (backlog-cfront/bug-c-an-unreferenced-external-stays-in-the-symbol-table-as-undefined). wlroots and Panorama call wl_fixed_from_double for real, so round is needed anyway |
| libxkbcommon 1.13.1 | all eight | bench/bench.c only (llroundl, through the macros of feature-crtl-long-double-math-aliases); the library itself needs none |

## What it amplifies

pxx drops an unused static inline's body but keeps an UND symbol for what
it called, so a header's unused helper adds a symbol to every unit that
includes it. gcc writes neither. That makes the gap look much wider than the
real calls are. Its own ticket:
backlog-cfront/bug-c-an-unreferenced-external-stays-in-the-symbol-table-as-undefined.

## Doing it

Definitions in lib/crtl/src/math.c, without copying any libm:
- `round`/`lround`/`llround`: half away from zero.
- `trunc`: toward zero, keeping -0.0.
- `modf`: integral part via trunc, keeping signs and infinities.
- `copysign`: by the sign bit.
- `log2`/`log10`: from the existing `log` with a correction, or proper
  argument reduction; exact at powers of 2 / 10 the way glibc is.

Each needs a row against gcc/glibc on edge values: ±0, ±inf, NaN, .5 cases,
large values, subnormals. Then rerun `tools/gen_crtl_map.py`.
