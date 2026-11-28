---
slug: feature-crtl-printf-h-parse-printf-format
track: crtl
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1, libsystemd/libudev census)
tags: [crtl, stdio, systemd]
summary: "crtl had no <printf.h>; 109 systemd units then took the host's, which pulls glibc's bits/floatn.h. systemd's VA_FORMAT_ADVANCE (src/basic/stdio-util.h) walks a va_list with parse_printf_format and the PA_* codes. Added: the PA_* enum and PA_FLAG_* values (glibc ABI) and parse_printf_format, written from the glibc manual (systemd's own musl fallback is LGPL and was not used). The length mapping follows glibc on x86-64 as measured, quirks included: ll/j/z/t are PA_FLAG_LONG, q and L add nothing on integers, %lc/%ls stay PA_CHAR/PA_STRING, every %n is PA_INT|PA_FLAG_PTR, ll/L/q on floats are long double. register_printf_function is not provided. Test c_prfh26: 25 templates against glibc, plus a check that the binary imports nothing."
---

# <printf.h>

A first version lived in src/printf_parse.c and the test passed by accident:
crtl pairs src/<header>.c with <header>.h, so the function was not in the
runtime, and the program imported glibc's parse_printf_format (the compiler
warned "crtl does not define parse_printf_format"). Hence the NEEDED check
in the row.
