---
slug: bug-c-a-later-declarators-const-after-the-star-was-not-skipped
track: C
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pxx (Gibux seat), rump-pxx S10 (NetBSD sys/device.h)
tags: [cfront, declarators, silent]
blocked-by: []
summary: "In `extern T * const a, * const b;` the second declarator stopped at `const`: every star loop in cparser.inc except ParseCDeclType's ate `*` and not the tkConst after it. b came out DEFINED (4 bytes of .bss, rump's `multiple definition`); a local `int * const p = &x, * const q = &y;` and a struct member list of that shape lost their values, silently. All eleven star loops (global/local declarators, struct members, typedef, sizeof/alignof) skip it now. Test: test/c_rump_silent.c (S10 line), test/c_extern_multi_const.c (nm: three U)."
---
