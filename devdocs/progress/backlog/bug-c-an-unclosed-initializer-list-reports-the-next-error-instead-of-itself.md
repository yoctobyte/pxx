---
slug: bug-c-an-unclosed-initializer-list-reports-the-next-error-instead-of-itself
track: C
prio: 30
type: bug
blocked-by: []
summary: "`int a[] = { 1, 2` with no closing brace reports `main function not found` — true, but not the error. The initializer walkers stop at EOF correctly; they simply do not say the list never closed, so the user is told about the second consequence."
status: backlog
---

# An unclosed initializer list reports the next error instead of itself

```c
int a[] = { 1, 2
```

```
pxx:  pascal26:1: error: main function not found
gcc:  error: expected '}' at end of input
```

Split from `bug-c-an-unterminated-declaration-still-parses-the-appended-pascal-rtl`.
That ticket gave the C token stream a real `tkEOF` and taught `CBlockContinues`
and `SkipBraceBlock` to refuse there, which fixed the struct and enum cases. The
initializer walkers (`CInitWalkArray`, `CInitWalkRecord`, `CInitSkipScalar`,
`CDeferScalarPtrInitSkip`, `CSkipCInitElement`) already test `tkEOF` and stop
correctly — **they just do not complain**, so the parse completes and the user
is told about the missing `main`, which is a real but secondary fact.

Milder than its siblings for that reason: nothing is consumed that should not
be, no Pascal is quoted, and the program does fail. It is a message pointing at
the second consequence instead of the cause.

## What to fix

Those walkers carry a `braced` flag. Reaching `tkEOF` while `braced` is the same
refusal `CBlockContinues` makes; `CRefuseUnterminated` already exists and words
it. Check each walker for whether the flag is in scope at the loop rather than
assuming it is.

## Gate

The example names the unclosed initializer on line 1. `cunterm*` and `cnomain`
stay green. 12 C corpus programs still compile. Self-host byte-identical.
