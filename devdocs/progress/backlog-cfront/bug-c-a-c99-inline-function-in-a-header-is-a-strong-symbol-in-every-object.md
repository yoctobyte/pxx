---
slug: bug-c-a-c99-inline-function-in-a-header-is-a-strong-symbol-in-every-object
track: C
prio: 55
type: bug
status: backlog
created: 2026-11-16
found-by: pixx-cc, building disk tools for pixx at 2491105c8d (repros: /data/projects/pixx/work/tooltest/repro/) B4
tags: [cfront, emit-obj, link]
blocked-by: []
summary: "A C99 `inline` (not static, not extern) definition in a header is emitted as a strong symbol in every object, so two objects that include it fail at --link with multiple definition. C99 6.7.4: a plain inline definition provides no external definition; gcc emits nothing (or a weak/COMDAT copy under gnu89). Repro c99inline_a.c/c99inline_b.c."
---
