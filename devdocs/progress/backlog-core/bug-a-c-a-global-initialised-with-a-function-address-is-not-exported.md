---
slug: bug-a-c-a-global-initialised-with-a-function-address-is-not-exported
title: "A C file-scope variable initialised with a function's address gets no OBJECT symbol"
track: A
prio: 40
type: bug
tags: [emit-obj, elf, symbols, cfront, linkage]
status: backlog
created: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "`fp_t F = helper;` is the ONE file-scope form the --emit-obj data work does not export. Swept seven shapes in one translation unit -- scalar with and without an initialiser, array, data pointer `int *P = &A;`, string pointer, struct -- and six get `OBJECT GLOBAL`; the function-pointer one gets no symbol at all. So another object referencing F links against its own private .bss and reads NULL, which is the silent-wrong-value shape the data work was filed to remove, surviving in one shape. Measured on x86-64 and riscv32 alike, so it is frontend, not writer."
---

# One shape out of seven

```c
int A = 1;            /* exported */    int *P = &A;        /* exported */
int B;                /* exported */    const char *S="hi"; /* exported */
int Arr[4] = {...};   /* exported */    struct {int x;} St; /* exported */
typedef int (*fp_t)(int);
int helper(int x){return x;}
fp_t F = helper;      /* NO SYMBOL AT ALL */
```

A DATA pointer initialiser exports and a CODE pointer initialiser does not, so
the cause is in whatever handles a function designator as an initialiser rather
than in the pointer-ness. Likely the declaration is consumed on a path that
never reaches the branch setting `SymObjDataScope`, the same way `extern` used
to be consumed in three separate loops without being recorded.

## Why it matters more than a missing symbol

This is exactly the callback-table shape — a file-scope array or variable
holding handler addresses, referenced from another translation unit. Under
separate compilation it links cleanly and the reader sees NULL, so the failure
is a call through a null pointer far from the declaration.

## Acceptance

- `F` gets `OBJECT GLOBAL` with the pointer's size, on x86-64, i386 and the ESP
  writers.
- A second object that references `F` relocates against the symbol, not its own
  `.bss` — the same two-sided check as
  [[bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link]],
  since a symbol that exists but is referenced section-relative still reads the
  private copy.
- An array of function pointers too, which is the real callback-table spelling
  and may take a different path again.
