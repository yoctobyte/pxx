---
slug: feature-crtl-c-utf8-locale
track: C
prio: 30
type: feature
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [crtl, toybox]
blocked-by: []
summary: "crtl supports only the C/POSIX locale, so utf8 cases in toybox's fold/fmt/echo/file tests differ from glibc's C.UTF-8. A C.UTF-8 locale (mbrtowc/wcwidth over UTF-8 when selected) would close them."
---

# crtl: C.UTF-8

setlocale(LC_ALL, "") with LANG=C.UTF-8 should select it.
