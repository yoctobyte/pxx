---
summary: "C: a parameter `R (fn (void *, T *))` stopped the parameter list -- glibc regcomp.c (git's compat/regex): `fn` and `extra` undeclared"
type: bug
prio: 40
---

# C: a parenthesised function parameter declarator is not read

- **Type:** bug (C frontend). Found 2026-11-28 building git 2.56.1 for the
  Nodisx git recipe (compat/regex/regcomp.c, glibc's regex).
- **Status:** done

## Symptom

```c
static reg_errcode_t preorder (bin_tree_t *root,
			       reg_errcode_t (fn (void *, bin_tree_t *)),
			       void *extra);
```

pxx: `undeclared identifier 'extra' used as value` and `call to undeclared
function: fn` in the body. gcc compiles it.

## Cause

C lets a declarator be parenthesised whole (C 6.7.6), so `R (fn (P))` is the
parameter `R fn (P)`. A function parameter is adjusted to a pointer to
function (6.7.6.3p8). The parameter reader in ParseCSubroutine knew `R fn
(P)`, `R (fn) (P)` and `R (*fn) (P)`. With a `(` before the name it named the
parameter `argN` and the list stopped there.

## Fix

Before the name, ParseCSubroutine takes the parentheses that wrap a function
declarator: each `(` after which comes the name and then `(`, or a
parenthesised name and then `(`. The function-type arm then reads the list
as for `R fn (P)`, and the same number of `)` is closed after it.

Handled spellings, each against gcc: `R (fn (P))`, `R ((fn) (P))`, `R ((fn
(P)))`, `R (fn (int v))`, and the ones that already worked. Still not read,
then and now: a name wrapped twice, `R ((fn)) (P)`. gcc accepts that too;
nothing seen so far writes it.

Test c_param_parenthesised_function_declarator (row c_ppfd26), against gcc
on x86-64 and i386: regcomp.c's preorder and postorder walking a tree, an
early stop, and seven spellings of one parameter.
