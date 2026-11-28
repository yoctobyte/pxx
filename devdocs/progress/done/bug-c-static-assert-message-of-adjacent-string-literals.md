---
slug: bug-c-static-assert-message-of-adjacent-string-literals
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libinput 1.31.1 through compdb.py replay)
tags: [cfront]
summary: "_Static_assert took exactly one string token as its message, so `static_assert(sizeof(T) == 4, 'sizeof(' #T ') must be ...')` failed with 'expected ')'' at the second literal. Adjacent literals concatenate in phase 6, here as anywhere. libinput's ASSERT_INT_SIZE. The parser now joins them, and a failing assertion prints the joined message. Test: c_fpcls26."
---

# C static assert message of adjacent string literals

CTryParseStaticAssert in cparser.inc.
