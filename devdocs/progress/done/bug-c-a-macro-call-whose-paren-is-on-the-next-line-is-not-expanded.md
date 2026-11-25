---
slug: bug-c-a-macro-call-whose-paren-is-on-the-next-line-is-not-expanded
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (Xorg for Path B)
tags: [cpreproc, macros]
summary: "A function-like macro's name ending a line with its `(` on the next line was left unexpanded: Xorg's dix/dixfonts.c, xf86Mode.c and rootlessCommon.c write `DebugF\n    (\"...\")`, and with DebugF defined empty the parser saw a call to an undeclared function. C 6.10.3p10 treats the newline as white space there. CPProcessText now peeks at the next line when the active line ends in a function-like macro's name and joins it when it starts with `(`; the parenthesis join then takes the rest. -g line numbers advance with the join. Test c_xgaps26."
---

# A macro call whose ( is on the next line is not expanded

```c
#define DebugF(...) /* */
DebugF
    ("[dix] Could not init font path element %s\n", name);
```

The peek leaves a line that does not start with `(` untouched, so an
object-like use of the same name, or a function name that merely matches
a macro, is not affected unless a `(` follows, which is when C expands it.
