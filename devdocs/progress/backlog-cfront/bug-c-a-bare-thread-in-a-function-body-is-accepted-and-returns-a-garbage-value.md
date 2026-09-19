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
summary: "`__thread int t;` inside a function body, with no `static`, is ACCEPTED and becomes an ordinary uninitialised stack local — measured 2026-09-19 at HEAD on x86-64: pxx returns a fresh indeterminate value per call (586162841, then 1551595657 on a rebuild) where gcc REFUSES the program outright (`function-scope 't' implicitly auto and declared `__thread`). SUMMARY CORRECTED THE SAME DAY, AND IT WAS BORN FALSE RATHER THAN GONE STALE: this said "with NO diagnostic", and the file was ADDED IN 09de09465 — the very commit whose warning falsifies it — so the sentence was never true for any reader. The remedy for that is not re-verifying later but deriving the summary from the tree you are COMMITTING TO rather than from the measurement you took before the fix. THE REMAINDER IS NARROWER THAN THE ORIGINAL SUMMARY AND STILL REAL: it now warns, and it still COMPILES and still returns garbage, where the oracle refuses. A warning is not a refusal, and acceptance for this ticket is the refusal. 09de09465 also got the TEXT wrong for one commit — it told the programmer this declaration "gets ONE copy shared by every thread", which is true of the `static` sibling and FALSE here, since this one is not shared at all but a fresh automatic; that is now a seventh reason (TLSREFUSE_FUNCAUTO) with its own message and its own warn-once flag, because two facts sharing one flag is the defect this family was rebuilt around, one size down. ONE CAUSE, TWO SPELLINGS — both come from cparser.inc's block-scope storage-class loop, which consumes `__thread`/`_Thread_local` and records only `static`, so the qualifier is gone before a symbol exists. The `static` sibling works single-threaded and is wrong only under threads; THIS one is wrong on one thread today and needs no threads to bite, which is why it outranks it. What is open is only whether we Error like gcc or keep warning — C requires a block-scope thread-local to be `static` or `extern`, so no correct program can want this shape and the population a refusal would break is empty by construction; measure it anyway before refusing, since that count went stale in eight days once already in this subsystem, in the flattering direction."
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

**THE "NO DIAGNOSTIC" CLAIM WAS BORN FALSE — IT WAS NEVER TRUE FOR ANY READER,
AND THAT IS A DIFFERENT DEFECT FROM A STALE SUMMARY.** My first account of this
said the sentence went stale four hours after I wrote it. Checked rather than
recalled, and it is worse than that: `git log --diff-filter=A` puts this file's
creation in **`09de09465`** — *the same commit as the warning that falsifies
it*. In that very tree `localSawThread := True` is set whether or not `static`
is present, and the warn fires before both declaration arms, so a bare
`__thread` warned at the exact revision that introduced the sentence saying it
does not.

**The remedy is not the one a stale summary needs.** "Re-verify the summary
before you start" does nothing here — there was no interval in which re-reading
would have helped, and the seat that files a ticket alongside a fix is the least
likely to re-read it. What catches this shape is: **derive the summary from the
tree you are COMMITTING TO, not from the measurement you took before the fix.**
The measurement (`586162841`, no diagnostic) was true when taken and false by
the time it was written down, and nothing in between announced the change.

That is CLAUDE.md's **born red** shape — a guard that could never have passed
once — arriving in a *summary* rather than an assertion, where nothing runs it
and so nothing reports it. An assertion written from a report of the code fails
loudly on arrival; a summary written from a superseded measurement just sits at
the top of a queue being read.

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
