---
slug: bug-a-default-emit-obj-objects-each-keep-private-crtl-state
track: A
prio: 60
type: bug
status: backlog
created: 2026-11-25
found-by: Nodisx toybox recipe (claude-pxx), 4 UTF-8 tests failing until --function-sections
tags: [emit-obj, link, crtl, object-model]
blocked-by: []
summary: "Two default --emit-obj objects (one .text, no --function-sections) linked together each keep THEIR OWN copy of crtl's file-scope static state -- about 91 variables: the stdio FILEs, strtok's cursor, the rand seed, getopt, the per-thread locale/ctype. srand in one object does not seed rand in another, strtok(NULL) in the second object segfaults, uselocale in one is invisible to wcwidth in the other. This contradicts the 2026-11-14 decision (decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit): self-contained objects are emitted MERGEABLE, one copy of the code AND one copy of the state. --function-sections objects behave (every call binds by symbol to the first object's copy), which is the recipes' workaround, not a fix."
---

# Default objects each keep private crtl state

## Repro (gcc is the reference)

`c.c`:

```c
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static void bye(void) { puts("atexit handler from c.o ran"); }
void seed(void) { srand(12345); atexit(bye); }
char *tok1(char *s) { return strtok(s, ","); }
```

`d.c`:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
void seed(void); char *tok1(char *);
int main(void) { char buf[] = "a,b,c"; int r1, r2;
  seed(); r1 = rand(); srand(12345); r2 = rand();
  printf("rand after srand in other unit matches: %d\n", r1 == r2);
  { char *t1 = tok1(buf); char *t2 = strtok(NULL, ",");
    printf("strtok continues across units: %s %s\n", t1, t2 ? t2 : "(null)"); }
  return 0; }
```

```
pascal26 --emit-obj c.c c.o; pascal26 --emit-obj d.c d.o
pascal26 --link -o p c.o d.o; ./p
```

gcc: matches 1, `strtok continues across units: a b`, the handler runs.
pxx default objects: matches 0, strtok(NULL) segfaults. With
`--function-sections` on both: same as gcc.

The locale variant (a.c calls `uselocale` on a UTF-8 locale, b.c calls
`wcwidth`/`mbrtowc`) is what broke toybox: main.c sets the locale, fold.c
reads the per-thread ctype through its own private copy, still "C".

## Why

A default object has one `.text`; calls inside it are baked rel32, and
crtl's file-scope `static`s are LOCAL symbols in its own `.data`/`.bss`. The
link binds GLOBAL names to the first definition, but each object's code still
reads its own locals. With `--function-sections` every cross-function
reference is a relocation and the losing copies' sections drop, so the state
is single by accident of GC, not by construction.

## What the decision asks for

Self-contained objects, mergeable: crtl's state must be exported (weak /
COMDAT) so N objects agree on ONE copy. Options, measured cost first:

1. Make `--function-sections` the default for `--emit-obj` (cheapest; the
   section machinery is already proven, feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes).
   Needs the local statics that crtl reaches through internal calls to be
   either weak globals or reached only through relocated code.
2. Promote crtl's file-scope statics to weak hidden globals with a reserved
   prefix in the object writer, so every object's copy binds to one.

Test: the c.c/d.c pair (and the locale pair) as a test-core row, default
objects, expected = gcc's output.

Related: `--shared-runtime` objects had a twin (their weak builtin-RTL copies
won over rt.o's, so atexit drained an empty table); fixed by loading the
runtime object first.
