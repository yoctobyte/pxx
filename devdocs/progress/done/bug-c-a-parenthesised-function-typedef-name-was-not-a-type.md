---
slug: bug-c-a-parenthesised-function-typedef-name-was-not-a-type
track: C
prio: 50
type: bug
status: done
created: 2026-11-16
found-by: pxx (Gibux seat), rump-pxx g07 (NetBSD sys/vmem.h vmem_import_t)
tags: [cfront, declarators]
blocked-by: []
summary: "`typedef int (imp_t)(int, int);` -- the name in redundant parentheses -- registered nothing; `imp_t *fn` was an unknown type. CUnparenTypedefName removes the pair (`( IDENT )` followed by `(`, `[` or `;`, IDENT not a type) before the arms run. Test: c_dcls."
---
