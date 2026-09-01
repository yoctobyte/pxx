---
slug: bug-a-c-a-global-initialised-with-a-function-address-is-not-exported
title: "No function-pointer global gets an OBJECT symbol — the initialiser was a red herring"
track: A
prio: 40
type: bug
tags: [emit-obj, elf, symbols, cfront, linkage]
status: done
created: 2026-09-01
found-by: frankA
owner: frankA
blocked-by: []
summary: "EVERY function-pointer file-scope variable was invisible to the object writer, not just an initialised one -- the slug is narrower than the defect. Swept seven forms in one TU: scalar, initialised, raw declarator `int (*G)(int);`, and a table all got no symbol, while the other six file-scope shapes exported. Cause: a fn-pointer declaration is registered by its OWN branch in cparser.inc which never recorded linkage; both branches now call CRecordGlobalLinkage. Fixed and covered on x86-64, i386, riscv32 and xtensa, with a two-object callback round trip against a gcc oracle.""
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

## Resolved — and the slug names the wrong variable

frankA, 2026-09-01. Compiler `4fa89436ffe7`. Regression rows: `test-emit-obj`
block 4b-ter-bis, four writers plus a two-object callback round trip against a
gcc oracle.

**The initialiser had nothing to do with it.** `fp_t F1;` with no initialiser
was equally invisible, and so was the raw declarator `int (*G1)(int);` and a
table `fp_t Tab[2]`. What the seven-form sweep actually bounded was
"function-pointer", not "initialised with a function address" — and I only
learned that by running the no-initialiser control, which the original ticket
did not contain. The slug is kept because it is cited elsewhere; the title and
summary are corrected.

**The cause is a second declaration path, not a missing case.** A
function-pointer global is registered by its own branch in `cparser.inc` —
it has to be, because the name sits inside the declarator and the ordinary
name-reading loop would break on the `=` or `;` and never register it — and
that branch never ran the linkage accumulation the general branch ran inline.
Nothing about function pointers made them unexportable; only which branch
registered them.

So the fix is the one `normalise-dont-special-case` asks for: the accumulation
became `CRecordGlobalLinkage` and BOTH branches call it. Adding a third copy of
the rule to the fn-pointer branch would have worked today and drifted later —
this is the arm that stayed broken for exactly that reason.

**Both sides of the contract, measured.** The census asserts the symbols exist
on x86-64, i386, riscv32 and xtensa. The round trip asserts they are reachable:
object A defines `Handler = dbl`, object B rebinds it to `inc`, and A's own
caller sees the change — `20 11`, matching gcc building the same two sources,
on x86-64 and i386. A symbol that exists but is referenced section-relative
would still read a private copy and print `20 20`.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3d5a36e79.
