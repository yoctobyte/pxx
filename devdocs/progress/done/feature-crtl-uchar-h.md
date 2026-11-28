---
slug: feature-crtl-uchar-h
track: crtl
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1, libsystemd/libudev census)
tags: [crtl, wchar, systemd]
summary: "crtl had no <uchar.h>, so 594 of systemd's 662 libsystemd/libudev units fell through to the host's, which pulls glibc bits/ headers (bits/floatn.h then fails on __GNUC_PREREQ in #if: 187 units' first error). Added from C11 7.28: char16_t, char32_t (char8_t under C23), mbrtoc16/c16rtomb/mbrtoc32/c32rtomb over crtl's C-locale mbrtowc/wcrtomb; c16rtomb holds a high surrogate in the state. Test: c_uchar26 against gcc+glibc."
---

# <uchar.h>
