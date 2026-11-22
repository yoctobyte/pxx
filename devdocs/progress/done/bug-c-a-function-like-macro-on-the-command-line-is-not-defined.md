---
slug: bug-c-a-function-like-macro-on-the-command-line-is-not-defined
track: C
prio: 40
type: bug
status: done
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, preprocessor]
blocked-by: []
summary: "DONE 2026-11-22: `'-DSQ(x)=((x)*(x))'` defined an object-like macro named `SQ(x)`, so SQ(7) was an undeclared call. A command-line name containing `(` now goes through CPDefine as the text `SQ(x) ((x)*(x))`, as a #define line would. Test c_cmdfnm26 (also `NOARGS()`, `#s`)."
---

# A function-like macro on the command line is not defined

gcc's `-D'name(args)=body'` defines a function-like macro. pxx's
CPApplyCmdlineDefines split at `=` and called CPAddLiteral(name, value), so
the macro was object-like and its name was the whole `SQ(x)`. Found
while defining `pthread_cancel(t)` away for the micropython build.

Fix: a name containing `(` is passed to CPDefine as `name body`, the text of
a `#define` line, so it gets the same parameter, `#` and `##` handling.
Test: test/c_cmdline_function_macro.c with five -D flags (row c_cmdfnm26),
which matches gcc.
