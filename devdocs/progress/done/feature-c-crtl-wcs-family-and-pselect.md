---
track: C
tags: [crtl, wchar, select, pathb, st]
prio: 70
type: feature
blocked-by: []
summary: "crtl's <wchar.h> had only wcslen and wcswidth; <sys/select.h> had no pselect. st (Path B's terminal) needs wcschr and pselect. Added the C99 wcs*/wmem* string and memory family and pselect over pselect6."
status: done
owner: pxx2
---

# crtl: the wcs/wmem family and pselect

- lib/crtl/src/wchar.c: wcsnlen, wcschr, wcsrchr, wcscmp, wcsncmp, wcscpy,
  wcsncpy, wcscat, wcsncat, wcsspn, wcscspn, wcspbrk, wcsstr, wcsdup, wmemchr,
  wmemcmp, wmemcpy, wmemmove, wmemset. These are plain loops; wchar_t is
  32-bit and signed, as in glibc.
- lib/crtl/src/sys/select.c: pselect over pselect6. The timeout is copied
  (the caller's is const), and the mask goes in the kernel's {set, 8} block.
  Where there is no pselect6 it returns ENOSYS.

Test: test/c_crtl_wcs_pselect.c (row c_wcspsel26) against gcc, x86-64 and
i386.
