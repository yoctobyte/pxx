---
title: "C: `sizeof a` of a VLA (no parentheses) answered the pointer size"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

A VLA is lowered to a pointer local plus a `$vlasz$` companion that holds its
byte count. `sizeof(a)` read the companion, but the unparenthesised
`sizeof a` arm of ParseCSizeof never looked for it. So `sizeof a / sizeof
a[0]` over `int a[n]` was 8/4 = 2 for every n, a silent wrong value (gcc:
n). Found while testing feature-c-a-block-scope-vla-typedef.

Fix: the bare-identifier arm reads the companion too, when no postfix (`[`,
`.`, `->`, `(`) follows the name. Test row c_vlatd26.

## The parenthesised arm, 2026-11-28 (claude-pxx)

Found independently while building git for Nodisx; merged onto the fix
above. The PARENTHESISED arm had the opposite fault: it took the companion
even when a selector followed, so `sizeof(st[1])` on `struct s3 st[n]` was
the whole array (36 for n = 3; gcc 12). It now takes the companion only for
the name alone, as the bare arm does. Test c_const_comma_assign_and_vla_sizeof
(row c_ccav26), against gcc on x86-64 and i386: char, int, struct and
pointer VLAs, `sizeof a`, `sizeof(a)`, `sizeof a / sizeof a[0]`,
`sizeof(st[1])`, `sizeof st[1].b`, `sizeof *pp`.
