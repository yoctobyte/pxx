---
slug: bug-c-a-named-variadic-macro-parameter-with-paste-is-undeclared
track: C
prio: 55
type: bug
status: backlog
created: 2026-11-16
found-by: pixx-cc, building disk tools for pixx at 2491105c8d (repros: /data/projects/pixx/work/tooltest/repro/) B1
tags: [cfront, preprocessor]
blocked-by: []
summary: "GNU named variadic `#define f(fmt, arg...) g(fmt, ## arg)` called with no extra arguments leaves `arg` in the output (\"undeclared identifier 'arg'\"); gcc drops the comma and the name. e2fsprogs lib/support/common.h:24. Repro named_variadic.c."
---
