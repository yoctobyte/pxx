---
slug: bug-c-builtin-clz-with-a-space-before-the-paren-is-undeclared
track: C
prio: 40
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (pixman for Path B Xorg)
tags: [cpreproc, builtins]
summary: "`__builtin_clz (x)` (a space before the parenthesis, as pixman-matrix.c writes it) in a file without <stdlib.h> gave `call to undeclared function: __pxx_builtin_clz32`. CAddBitBuiltins detected the families only by `__builtin_<name>(`, so no static helper was injected. It now also accepts a following space, as CAddFreestandingBuiltins already did for prototypes. Test c_xgaps26."
---

# __builtin_clz with a space before the paren is undeclared

Hosted builds get crtl's helper from <stdlib.h>; a unit that does not
include it relies on the injected static copy, which the space defeated.
