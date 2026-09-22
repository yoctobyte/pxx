---
slug: bug-a-xtensa-cannot-lower-a-store-through-a-pointer-so-no-c-program-that-writes-through-a-parameter-compiles
title: "xtensa: a store through a pointer is IR_UNSUPPORTED (AN_BINOP), so no C program that writes through a pointer parameter compiles"
track: A
prio: 60
type: bug
status: open
created: 2026-09-22
found-by: frankb-8e
owner:
blocked-by: []
summary: "`char *f(char *d){ *d = 0; return d; }` at `--target=xtensa --emit-obj` gives `IR_UNSUPPORTED: frontend could not lower AST node (kind 5)` -- AN_BINOP, the C frontend's assignment-expression form. The same source compiles for riscv32, i386 and x86-64. It is the STORE and not the dereference: a pointer READ through the same parameter (`char f(char *d){ return *d; }`) compiles on xtensa fine, and an int store fails identically, so it is neither width- nor const-specific. The blast radius is the whole crtl: `lib/crtl/src/string.c` refuses at line 188 (`*d = '\\0'` in `strncat`), so ANY xtensa C program that calls a crtl-provided libc routine -- `strlen`, `puts`, `printf` were each measured -- fails at that line while a program calling only its own functions compiles. WHY NOBODY HAS HIT IT: xtensa has no C entry stub (`C program entry stub on xtensa: a STANDALONE...`), so `--emit-obj` is the only C route on that target and nothing in the tier drives it with a libc call. Found while trying to give xtensa a probe for tools/reloc_resolve_check.py; the harness reported SKIP with the real diagnostic rather than a pass, which is how it surfaced."
---

# Reduction

```c
char *f(char *d){ *d = 0; return d; }     /* xtensa: IR_UNSUPPORTED kind 5 */
char  g(char *d){ return *d; }            /* xtensa: ok */
```

| shape | xtensa | riscv32 |
| --- | --- | --- |
| `*d = 0` (char store through a param) | **IR_UNSUPPORTED kind 5** | ok |
| `*d = 65` (non-zero) | **IR_UNSUPPORTED kind 5** | ok |
| `d++; *d = 0` | **IR_UNSUPPORTED kind 5** | ok |
| `void f(char *d){ *d = 0; }` (result unused) | **IR_UNSUPPORTED kind 5** | ok |
| `int *f(int *d){ *d = 0; ... }` | **IR_UNSUPPORTED kind 5** | ok |
| `return *d` (read, same parameter) | ok | ok |

So: the STORE, any width, whether or not the value or the pointer is used
afterwards. Not the dereference, not the constant, not `char`.

`AN_BINOP = 5` (`defs.inc:745`) is the C frontend's assignment-expression node.
The lowering that handles it is reached on riscv32 and not on xtensa, which
says the store path branches on target somewhere it should not — the two ESP
backends are otherwise the pair that share this shape.

# What it costs today

`lib/crtl/src/string.c:188` is `*d = '\0'` in `strncat`. Compiling that file
alone for xtensa refuses at 188, so every xtensa C program that pulls crtl in
refuses at the same line — measured with `strlen`, `puts` and `printf`, each
of which resolves to a crtl implementation. A program that calls only its own
functions, or declares an external pxx does not implement, compiles.

**The line number is the imported unit's and carries no file name**, which is
the usual trap: three unrelated programs all report `pascal26:188` and it reads
as one shared cause in the SUBJECT. It is one shared cause, in `string.c`.

# Why it has stayed invisible

`--target=xtensa` refuses a C *executable* outright (`C program entry stub on
xtensa: a STANDALONE ...`), so `--emit-obj` is the only C route on xtensa, and
nothing in the tier drives an xtensa C object that calls libc. The ESP rows in
`test-emit-obj` build Pascal.

**Whether the Pascal frontend has the same gap is NOT measured here.** The
reduction and the whole table above are C. Someone should check before assuming
this is C-only.

# Found by

Writing an xtensa probe for
[[feature-a-a-target-generic-resolve-and-compare-harness-for-emit-obj-objects]].
The harness printed `SKIP -- pxx cannot emit an object here` with the compiler's
own diagnostic rather than passing over the target, which is the only reason it
was seen. Filed rather than routed past, so the next person to write an xtensa
probe does not rediscover it.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]
