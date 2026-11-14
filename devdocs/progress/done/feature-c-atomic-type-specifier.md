---
track: C
tags: [C, atomics]
prio: 30
type: feature
summary: "The _Atomic(T) type specifier now parses: the lexer drops `_Atomic(` and its matching `)`, leaving T, as the _Atomic qualifier was already treated. Storage and layout equal T's, as on gcc for the sizes pxx supports. Plain operators on an _Atomic object are still not atomic; use the builtins or <stdatomic.h>."
status: done
owner: unassigned
found: 2026-11-14
---

# C: the `_Atomic(T)` type specifier

`_Atomic(int) x;` and `_Atomic(struct s *) p;` were refused as a parse
error. `compiler/clexer.inc` CSkipSpace now recognises `_Atomic(`, drops it,
and pushes the current paren depth on CLexAtomicStack; the `)` that brings the
depth back to it is skipped as well. The counters reset in CLexAll and
CLexAppend so a failed TU cannot leak a pending pop into the next one.

The `_Atomic` qualifier (no paren) was already accepted and ignored, so the two
spellings now behave the same.

Verified: a probe mixing `_Atomic(int)`, `_Atomic(long long)` and
`_Atomic(int *)` with `atomic_fetch_add`, `atomic_load` and `sizeof` prints the
same as gcc.

## Not done

Plain `x++` on an `_Atomic` object is an ordinary increment, not a locked one.
gcc makes it atomic. A program that relies on that must use the builtins.
