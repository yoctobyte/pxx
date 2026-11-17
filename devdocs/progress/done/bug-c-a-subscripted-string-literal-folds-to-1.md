---
track: C
tags: [C, cfront, const-eval, crtl, busybox]
prio: 30
type: bug
blocked-by: []
summary: "In a C constant expression, \"abc\"[i] folded to 1, the truth value of the literal's address, because CEvalConstPrimary's string arm never read the subscript. busybox's BUILD_BUG_ON(CONFIG_BUSYBOX_EXEC_PATH[0] != '/') then became char[-1] and stopped the build of libbb/vfork_daemon_rexec.c. It now folds to the character (plain char's signedness for a high byte), the terminating NUL at index = length, and refuses a subscript beyond that. Also from the same BusyBox build: crtl's <unistd.h> gains getpgrp(), which is getpgid(0) and is used by hush."
status: done
owner: unassigned
---

# A subscripted string literal folded to 1

pxx2 found both while building BusyBox 1.36.1 (NOMMU, hush) per translation unit for Gibux. Repros: /data/tmp/pxxrepro/strlit_const.c and getpgrp.c.

## Cause
The tkString arm of CEvalConstPrimary was written so that `"opts" || 0` folds to 1 (toybox). It skipped the literal and returned 1 without looking for a `[`.

## Fix
The arm collects the literal's text. If a `[i]` follows, it evaluates i as a constant and returns the character:
- Plain char's signedness decides a high byte (CPlainCharSigned).
- i equal to the length gives 0, the terminating NUL.
- i beyond the length is an error.

## Test
test/c_busybox_hush_gaps.c covers the BUILD_BUG_ON, a static const initialised from "abcdef"[4], sizeof(char["ab" "cd"[3]]), and getpgrp() == getpgid(0). It is wired in test-xtensa on x86-64 and on hosted xtensa, against gcc's output. The old compiler fails with "array dimension is negative (-1)".
