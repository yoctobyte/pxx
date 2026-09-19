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
summary: "`__thread int t;` inside a function body, with no `static`, is ACCEPTED and becomes an ordinary uninitialised stack local — measured 2026-09-19 at HEAD on x86-64: pxx returns a fresh indeterminate value per call (586162841, then 1551595657 on a rebuild) where gcc REFUSES the program outright (`function-scope 't' implicitly auto and declared `__thread`). SUMMARY CORRECTED THE SAME DAY: this said "with NO diagnostic", and 09de09465 — my own landing, hours later — made that false by warning here too. THE REMAINDER IS NARROWER THAN THE ORIGINAL SUMMARY AND STILL REAL: it now warns, and it still COMPILES and still returns garbage, where the oracle refuses. A warning is not a refusal, and acceptance for this ticket is the refusal. 09de09465 also got the TEXT wrong for one commit — it told the programmer this declaration "gets ONE copy shared by every thread", which is true of the `static` sibling and FALSE here, since this one is not shared at all but a fresh automatic; that is now a seventh reason (TLSREFUSE_FUNCAUTO) with its own message and its own warn-once flag, because two facts sharing one flag is the defect this family was rebuilt around, one size down. ONE CAUSE, TWO SPELLINGS — both come from cparser.inc's block-scope storage-class loop, which consumes `__thread`/`_Thread_local` and records only `static`, so the qualifier is gone before a symbol exists. The `static` sibling works single-threaded and is wrong only under threads; THIS one is wrong on one thread today and needs no threads to bite, which is why it outranks it. What is open is only whether we Error like gcc or keep warning — C requires a block-scope thread-local to be `static` or `extern`, so no correct program can want this shape and the population a refusal would break is empty by construction; measure it anyway before refusing, since that count went stale in eight days once already in this subsystem, in the flattering direction."
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
| pxx | compiles, **warns since 09de09465**, and still prints a garbage value (**586162841**, then **1551595657** on a later build — it is indeterminate, so the digits are not the finding) |

**THE "NO DIAGNOSTIC" CLAIM WAS TRUE WHEN FILED AND WAS FALSE FOUR HOURS
LATER**, falsified by this ticket's own author landing `09de09465` in the same
seam. Corrected in the commit that did it. That is the mechanism CLAUDE.md
gained a clause for today, arriving on a summary written the same evening by
the person best placed to know — which is the point: your own text reads as
already-checked.

**The remainder is narrower and still real.** A warning is not a refusal, and
the acceptance criterion here is the refusal: gcc rejects the program outright,
and we build it and hand back a garbage value.

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
