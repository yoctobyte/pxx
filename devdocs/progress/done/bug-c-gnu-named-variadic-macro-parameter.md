---
track: C
tags: [cpreproc, macros, variadic, rump, netbsd]
prio: 50
type: bug
blocked-by: []
summary: "GNU named variadic macros, `#define LOG(lvl, fmt, args...) log(lvl, fmt, ##args)` (NetBSD SPPP_LOG), bound `args` as an ordinary parameter: called with no variadic arguments it was \"undeclared identifier 'args'\". Also `#__VA_ARGS__` was never stringified (left as text, it swallowed the rest of the file into a string), with `...` or a named variadic. rump-pxx g33."
status: done
owner: pxx2
---

# GNU named variadic macro parameters

cpreproc.inc CPDefine: `name...` is not a parameter; the macro is variadic
and the body's `name` becomes `__VA_ARGS__` (CPRenameIdent, outside literals),
so `, ## name` drops the comma like `, ## __VA_ARGS__`. CPExpandFunction
stringifies `#__VA_ARGS__` as the variadic arguments' text with white-space
runs collapsed, as gcc does.

Test: test/c_rump_small_fold.c (LOG with none and two variadic arguments,
`#args`, a named head before `rest...`) against gcc.
