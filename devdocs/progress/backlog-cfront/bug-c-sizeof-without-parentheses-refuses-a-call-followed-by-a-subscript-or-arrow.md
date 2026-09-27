---
track: C
prio: 30
type: bug
status: open
found: 2026-09-27
found-by: frankD
owner:
summary: "LOUD, not silent: `sizeof f()[1]` (int *f(void)) and `sizeof h()->a` fail with `expected ')'` at the call; gcc accepts both (24 for the pair in the repro). `sizeof f()` and `sizeof *f()` compile. Parenthesising the operand, `sizeof(f()[1])`, works."
---

# `sizeof` without parentheses refuses a call followed by `[i]` or `->`

```c
int g[3] = {1, 2, 3};
int *f(void) { return g; }
struct S { int a[5]; } s;
struct S *h(void) { return &s; }
int main(void) { return (int)(sizeof f()[1] + sizeof h()->a); }   /* gcc: 24 */
```

pxx: `pascal26:4: error: expected ')'  near: sizeof f >>>`. Each of the two
operands fails alone; `sizeof f()` and `sizeof *f()` compile, and so does the
parenthesised `sizeof(f()[1])`. Measured 2026-09-27 on HEAD (compiler
848d33f2668a). A refusal, so no program gets a wrong answer; the postfix chain
after a call inside the `sizeof` unary operand is what is not parsed.
