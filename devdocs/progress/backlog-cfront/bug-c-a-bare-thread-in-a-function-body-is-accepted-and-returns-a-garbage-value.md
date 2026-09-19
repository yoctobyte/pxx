---
slug: bug-c-a-bare-thread-in-a-function-body-is-accepted-and-returns-a-garbage-value
track: C
prio: 55
type: bug
status: backlog
created: 2026-09-19
found-by: frankS
tags: [tls, threads, c-frontend]
blocked-by: []
summary: "`__thread int t;` inside a function body, with no `static`, is ACCEPTED and becomes an ordinary uninitialised stack local — measured 2026-09-19 at HEAD on x86-64: pxx returns 586162841 with NO diagnostic where gcc REFUSES the program outright (`function-scope 't' implicitly auto and declared '__thread'`). This is a WRONG VALUE TODAY, ON ONE THREAD, and it does not need threads to bite, which is what separates it from its sibling: the same seam's `static __thread` case works single-threaded and is wrong only under threads. ONE CAUSE, TWO SPELLINGS — both come from cparser.inc's block-scope storage-class loop, which consumes `__thread`/`_Thread_local` and records only `static`, so the qualifier is gone before a symbol exists. The sibling's SILENCE is fixed (a warning now fires, `bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-...`); this row is not, and it is deliberately not folded in because refusing it is a BEHAVIOUR CHANGE on something that compiles today and needs its own measurement — the precedent is the comment above that same loop, which left `extern` out for exactly that reason. The measurement now exists. C requires a block-scope thread-local to be `static` or `extern`, so no correct program can want this shape; the open question is only whether we Error like gcc or warn."
---

# A bare `__thread` at block scope compiles to a garbage stack local

## Measured

HEAD, x86-64, 2026-09-19, gcc as the oracle on the same source:

```c
int bump(void) { __thread int t; t++; return t; }   /* no `static` */
```

| compiler | result |
| --- | --- |
| gcc | **refuses**: `error: function-scope 't' implicitly auto and declared '__thread'` |
| pxx | compiles, no diagnostic, prints **586162841** |

Its sibling — the same declaration **with** `static` — prints `1 2 3` under both
compilers and is correct single-threaded.

## The cause is one line, and it is the same line as the sibling's

`cparser.inc`, the block-scope storage-class loop in `ParseCStatementAST`. It
consumes `register|auto|static|__thread|_Thread_local` and records only
`localSawStatic`. So:

- **with `static`** — storage is right, and the thread-local request is lost.
  That was silent until 2026-09-19 and now warns (`TLSREFUSE_FUNCSCOPE`).
- **without `static`** — `localSawStatic` stays false, the declaration falls
  through to the ordinary-local path, and the program gets an uninitialised
  automatic. **This row.**

**That is the "one seam, two spellings" shape**, and finding the second spelling
is what makes the first fix trustworthy rather than a patch on the case somebody
happened to try.

## Why it is filed separately and ranked above its sibling

Refusing this is a behaviour change on something that compiles today, which the
comment above that very loop already settled the discipline for — `extern` was
deliberately left out of the set because *"adding it is a behaviour change this
fix has no measurement for"*. **The measurement now exists**, so this earns a
ticket rather than a bolt-on.

It outranks the sibling because of what the two actually cost. The sibling is a
program that **works single-threaded** and is wrong only once threads exist.
This one is a **wrong value on one thread, today, with nothing to notice it
by** — and it is a program the oracle rejects outright, so no correct source can
depend on the current behaviour.

## What to decide

Error like gcc, or warn? **This is not the warn-versus-error question the
file-scope path answered** and must not be settled by citing it. There, four of
the five refusals are OUR limits and refusing would delete `__thread` from
programs that are **correct** today. Here there is no such population: C
requires a block-scope thread-local to be `static` or `extern`, so every program
reaching this row is already wrong and gcc already refuses it.

An Error is the honest answer and the argument against it is weak — but it is
still a refusal of something that builds today, so whoever takes it should
measure the in-tree and busybox populations first rather than assume zero. That
count went stale in eight days once already in this subsystem, in the
flattering direction.

## Positive control

A fixture asserting the refusal must also assert that `static __thread int t;`
in a body **still compiles**, or it passes on a change that refuses the whole
block-scope family — which is the sibling's working case and the exact
whole-family shape that has certified a broken half here before.
