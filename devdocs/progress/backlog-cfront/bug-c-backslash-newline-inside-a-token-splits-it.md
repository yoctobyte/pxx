---
slug: bug-c-backslash-newline-inside-a-token-splits-it
track: C
prio: 50
type: bug
status: open
found: 2026-11-28
found-by: pxx2 (while writing the __LINE__ repro)
owner:
summary: "A backslash-newline in the middle of an identifier (`ma\\<newline>in`, `__LINE\\<newline>__`) is not removed before tokenizing, so the identifier splits in two and the unit is refused (`near: ma >>> in`). C translation phase 2 deletes every backslash-newline before phase 3 forms tokens, so gcc reads `main` and `__LINE__`. Rare in hand-written code; it occurs in generated and minified sources and in conformance suites."
---

# A backslash-newline inside a token splits it

```c
int ma\
in(void) { int a\
b = 3; return a\
b; }
```

gcc: compiles, exits 3. pxx: `near:  ma >>> in`.

Splices are handled at line ends (directive continuation, the in-comment
splice at cpreproc.inc ~3078/3105), but not as a phase-2 removal ahead of
tokenizing. Fix where CPReadLine builds the logical line: drop each
backslash-newline pair and count the physical line (-g line numbers must
still advance).
