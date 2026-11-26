---
slug: bug-c-an-alias-in-an-executable-becomes-a-dynamic-import
track: C
prio: 55
type: bug
status: backlog
created: 2026-11-26
found-by: pxx2 (while testing bug-c-the-alias-attribute-was-ignored)
tags: [cfront, symbols, silent, elfwriter]
blocked-by: []
summary: "In a whole-program build (no --emit-obj), an alias -- file-scope `__asm(\".globl add\\nadd = impl_add\")` or `__attribute__((alias(\"impl_add\")))` -- is not emitted: a call to `add` becomes a dynamic import and the program dies at start with `symbol lookup error: undefined symbol: add`. The object path (writeELFRelX64General) handles both. The executable writer should bind the alias name to the target's body (or refuse at compile time); today it fails only at run time."
---

# An alias in an executable becomes a dynamic import

```c
int impl_add(int a, int b) { return a + b; }
__asm(".globl add\nadd = impl_add");          /* or: */
/* int add(int, int) __attribute__((alias("impl_add"))); */
int add(int, int);
int main(void) { return add(2, 3) - 5; }
```

`pascal26 x.c x` compiles and links; `./x` prints
`symbol lookup error: ./x: undefined symbol: add`.

The aliases are recorded (CFsaAlias*) and consumed only by the object writer
(elfwriter.inc, ObjPlanFsaAliases). The executable path resolves a call to
an undefined-here name as an import.

Fix direction: in the executable path, resolve a call/address of an alias
name to the target's proc or symbol (the alias is the same address), before
import binding. At least refuse at compile time, naming the alias, rather
than leave a run-time failure.

Not urgent for Nodisx (every recipe builds with --emit-obj); left because
elfwriter.inc was another session's area that day.
