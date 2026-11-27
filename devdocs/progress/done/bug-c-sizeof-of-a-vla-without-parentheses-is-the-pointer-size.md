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
