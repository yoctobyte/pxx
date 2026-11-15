---
slug: bug-c-a-multi-name-typedef-declares-only-its-first-name
track: C
prio: 60
type: bug
status: backlog
created: 2026-11-15
found-by: rump-pxx g23, re-measured while fixing S10
tags: [cfront, declarators]
blocked-by: []
summary: "`typedef int ta, tb;`, `typedef struct {...} S, *PS;` and `typedef int *a, *b;` register only the first name: every arm of ParseCTypedef (struct body, tagged struct, enum, generic) takes one name and skips to `;`. Loud (the later name is `undeclared identifier`), not silent. Each arm needs a comma loop that re-derives the type from the base plus the declarator's own stars."
---
