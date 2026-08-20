---
track: C
prio: 60
type: bug
summary: "RE-TYPED 2026-08-19 feature -> bug (it was already described as a silent wrong value in its own body). MEASURED on v363: with `extern char **environ;` declared, pxx compiles CLEAN — no warning at all — and the program prints a NULL pointer where gcc prints the real environment. `char **envp = environ;` silently becomes NULL in a C program: environ is a VARIABLE read directly, with no call to trigger crtl's lazy /proc/self/environ load, and the C entry stub has no init phase. The fini half landed 2026-08-10; this is the init half"
---

# The C entry stub needs an INIT phase, for `environ`

- **Type:** feature (silent wrong value) — **Track C** (the C entry stub), with
  a Track A half if the shell moves
- **Opened:** 2026-08-10, splitting the remaining half out of
  [[feature-c-entry-stub-must-run-finalizers]] when that landed.

## Why it is split rather than left implied

That ticket's 2026-08-09 note said one entry-stub change unblocks both `atexit`
and `environ`. That is true of the *place*, not of the *change*: they are
opposite ends of the stub.

- **fini** — run `__pxx_run_finalizers` after `main` returns. **Landed
  2026-08-10** on all five targets.
- **init** — run something *before* `main` is called. **Not done**, and nothing
  in the landed change gets it.

Leaving it implied by a closed ticket is how a silent-wrong-value defect
disappears from the board, so it gets its own entry.

## Measured (unchanged by the fini work)

```
warning: undeclared identifier 'environ' used as value (treated as 0)
```

so `char **envp = environ;` is NULL. Found bringing up tcc
([[feature-crtl-implement-libc-assumptions]]); `tcc.c` builds and runs but sees
no environment.

crtl already HAS the data — `stdlib.c` loads `/proc/self/environ` into
`pxx_env_buf` for `getenv()`. The blocker is that `environ` is a **variable read
directly**, so no call triggers the lazy load; it must be populated before
`main` runs.

## Shape of the fix

Mirror what landed for the fini side: the stub already has the initial stack
pointer saved (`BSS_INITIAL_RSP`) and hands `main` argc/argv from it — `envp`
sits immediately after the argv NULL terminator on the Linux initial stack, so
the data is right there. Either:

1. **call a `__pxx_run_initializers` shell** before `call main`, symmetric with
   the finalizer runner and reusable by anything else needing pre-main work
   (this is the shape to prefer — it is one mechanism, not an `environ` special
   case); or
2. have crtl export `environ` as a real symbol that the stub fills from the
   saved stack pointer.

Prefer (1). (2) is an `environ`-shaped hole that the next pre-main requirement
would have to duplicate — the failure mode
`devdocs/dev/normalise-dont-special-case.md` is about, and which this repo has
paid for repeatedly (four parameter parsers, two default-arg builders).

Note the ordering constraint: the initializer call must not clobber argc/argv
before `main` receives them — on x86-64 they are already in edi/rsi at that
point, so the save/restore is the mirror of the fini side's.

## Gate

`char **envp = environ;` giving a usable environment, diffed against gcc via
`tools/gcc_diff_probe.sh`; the C suites green (the stub is on every C program's
path); the finalizer test `test/cfinalizers_on_main_return_b379.c` still
passing, since both now live in the same stub.

## Triage 2026-08-19 (Track D re-triage pass, pin v363) — RE-TYPED feature -> bug

```c
#include <stdio.h>
extern char **environ;
int main(void){ char **e = environ; printf("%p %s\n", (void*)e, e ? e[0] : "(NULL)"); }
```

| | output |
| --- | --- |
| pxx, pin v363 | `0x0 (NULL)` |
| gcc | `0x7fff… SHELL=/bin/bash` |

Two things the ticket did not have:

- **The diagnostic is gone.** The ticket quotes `warning: undeclared identifier
  'environ' used as value (treated as 0)`. With the declaration C code
  actually writes — `extern char **environ;` — v363 emits **no warning**. The
  build is clean and the value is wrong, which is strictly worse than the state
  on record.
- The body already called this "(silent wrong value)" in its own type line
  while the frontmatter said `feature`. That mismatch is the ranking error the
  mandate is about; the frontmatter now agrees with the body.

The fix shape in the ticket is unchanged — the C entry stub still has no init
phase, and crtl still holds the data it cannot reach.

## 2026-08-20 — RAISED 45 -> 60 (coordinator), and the reason is the ticket's own re-typing

This was re-typed feature -> bug on 2026-08-19 because it is a **silent wrong value**, and
then left at the prio it had as a feature. Ranking did not follow the re-typing.

By the repo's own escape rule a defect that produces a wrong value with no diagnostic is
ranked as the bug it is, not as the feature it was filed as. This one is worse than the
generic case on two counts:

- It **compiles clean** at v363 — no warning at all — so nothing at the call site suggests
  anything happened. (Note the body's earlier `warning: undeclared identifier` transcript
  predates that measurement; with `extern char **environ;` declared there is no warning.
  Two snapshots, different conditions — the 2026-08-19 one is current.)
- It is on **every C program's path**. `tcc.c` builds and runs and sees no environment at
  all, which is the kind of failure a corpus target absorbs silently.

Second, structural reason to rank it now: the ticket already contains the design call —
**prefer shape (1), a `__pxx_run_initializers` shell, over (2), exporting `environ` from
crtl.** (2) is an `environ`-shaped hole the next pre-main requirement duplicates, which is
the `normalise-dont-special-case` failure this repo has paid for repeatedly. That decision
decays if the ticket sits: the longer it waits, the more likely the next person takes the
narrow route because it is smaller. Ranking a decided design is cheap; re-deciding it after
someone has built the special case is not.

The fini half landed 2026-08-10 on all five targets and the mechanism is symmetric, so this
is the second end of a stub that already works.
