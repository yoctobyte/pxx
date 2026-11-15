---
slug: bug-c-attribute-mode-qi-hi-si-di-was-ignored
track: C
prio: 65
type: bug
status: done
created: 2026-11-15
found-by: pxx (Gibux seat), rump-pxx S6
tags: [cfront, attributes, silent]
blocked-by: []
summary: "`typedef int di_t __attribute__((mode(DI)));` was 4 bytes (gcc 8) and `mode(QI)` 4 (gcc 1): only the 128-bit modes were looked at (refused), the rest skipped. The lexer now puts the width (QI/byte 1, HI 2, SI 4, DI 8, word/pointer = pointer size) on the next token (CAttrFlags bit 128, CAttrAlignValues bits 24..31; the aligned value is bits 0..15 and its readers mask it), and ParseCTypedef makes an integer type that wide with its signedness, wherever the attribute sits in the declaration. Typedefs only; a mode on a variable or member is still ignored. Test: test/c_rump_silent.c (S6 line)."
---
