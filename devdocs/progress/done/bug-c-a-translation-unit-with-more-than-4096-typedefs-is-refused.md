---
title: "C: a translation unit with more than 4096 type aliases was refused"
status: done
owner: claude-dupwt
prio: 60
area: cfront
---

i915's intel_dp_link_training.c, with the LinuxKPI and drm headers it pulls
in, declares more than 4096 typedefs. The type-alias table (C typedefs share
it with Pascal type aliases) is a set of static arrays sized by MAX_TYPEALIAS
= 4096, so the compile stopped with "too many type aliases". Found in the
GPU-driver census (feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix: MAX_TYPEALIAS = 16384 (defs.inc). The arrays are zeroed memory, and
nothing loops over the whole table or bakes the bound into the builtin
layout, so the binary is the same size and a small compile costs the same
(2.5 s / 64 MB against 2.7 s / 65 MB). intel_dp_link_training.c now compiles
in 13.4 s with a 310 MB peak.

No new test row: a 4097-typedef test only proves a constant.
