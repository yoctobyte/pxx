---
track: C
prio: 60
type: bug
summary: "RE-TYPED 2026-08-19 feature -> bug (it was already described as a silent wrong value in its own body). MEASURED on v363: with `extern char **environ;` declared, pxx compiles CLEAN — no warning at all — and the program prints a NULL pointer where gcc prints the real environment. `char **envp = environ;` silently becomes NULL in a C program: environ is a VARIABLE read directly, with no call to trigger crtl's lazy /proc/self/environ load, and the C entry stub has no init phase. The fini half landed 2026-08-10; this is the init half"
status: done
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

## RESOLVED 2026-08-20 (frank2-C) — shape (1), five targets, no Track A half

Landed as `08dccc7df` (self-hosted fixedpoint, `gate.sh quick` GREEN). The
whole diff is `compiler/cparser.inc`, `lib/crtl/**`, one test and its Makefile
line — **the shell did not move, so there is no Track A half after all.**

### What was built

Shape **(1)**, as the ticket asked and for the reason it gave. The stub calls a
general `__pxx_run_initializers` shell; the shell lives in `lib/crtl/src/
unistd.c` and receives the **raw Linux initial stack pointer** — the one thing
only the stub knows — deriving `environ` from it in C:

```c
void __pxx_run_initializers(long *sp)
{
  long argc = sp[0];
  environ = (char **)(sp + argc + 2);
}
```

That choice is what keeps it from being an `environ`-shaped hole in practice
and not just in name: the next pre-main requirement is a **statement in this
function**, in C, rather than a sixth hand-assembled per-target stub sequence.
`long` is exactly one stack slot on every target pxx builds for (8 on LP64, 4
on ILP32), so the pointer arithmetic scales itself and one C body serves all
five.

### The ordering constraint dissolved rather than being handled

The ticket warns that the initializer call must not clobber argc/argv before
`main` receives them. It does not have to be handled at all if the call is
placed **before** argc/argv are loaded into the argument registers: at that
point nothing is live except the stack pointer, which the callee preserves. So
there is no save/restore mirroring the fini side — there is nothing to save.
The one exception is i386, which keeps its scratch copy of sp in `eax` across
that region and reloads it from `BSS_INITIAL_RSP` after the call.

### Activation is demand-driven; the mechanism is not

A program that never names `environ` emits **byte-identical code** — no call,
no pull. The trigger is one length-filtered identifier scan over the token
stream, which is the same demand-driven shape every other crtl pull in
`cparser.inc` already uses (`CPullCrtlForPrototypes`'s two sweeps look for
`name(` and therefore structurally cannot see a variable — which is the actual
reason this defect survived).

The predicate `CNeedsEnvironInit` is called from **both** the stub and the crtl
pull deliberately: if those two disagreed, the stub would call an address that
was never filled. They cannot disagree because they are one function, and the
patch site errors loudly rather than leaving a wrong address if the body is
somehow absent.

The two stub call sites (`main` and the initializer) now share one
`CPatchStubCall` helper — one copy of the per-target call-encoding table where
there would otherwise have been two.

### Gate

| check | result |
| --- | --- |
| `environ` vs gcc, x86_64 / i386 / arm32 / aarch64 / riscv32 | identical on all five |
| `test/cfinalizers_on_main_return_b379.c` (the fini half) | passes |
| `test/c_environ_prefilled_b380.c` (new, wired into `test-core`) | 42 on all five targets |
| `test/ctcc_parse_batch_b184.c`, `ctcc_batch2_b185.c` | 42 |
| quickjs runner (declares `extern char **environ;`) | builds; behaviour **identical to the pinned baseline** |
| `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` | GREEN |

The new test is deliberately **self-consistent**: it asserts nothing about
which variables the environment holds, only that every entry is `NAME=VALUE`
and that `getenv()` of the first entry's own name returns that entry's own
value. A test that wanted `PATH` would be testing the build machine.

`tools/gcc_diff_probe.sh` was NOT given a case, and that is deliberate: it
builds its pxx side with `PXX_STABLE`, so a case added now would be red until
the next pin and would read as a regression rather than as a pending fix. Add
it when this is pinned.

### One divergence from gcc, recorded rather than hidden

A program that **defines** `char **environ;` itself (rather than declaring it
`extern`) gets ours filled, where gcc leaves that program's own zero-initialised
object alone. POSIX reserves the name for the implementation, and every real
user in this repo's corpora writes `extern char **environ;` (tcc's `tccrun.c`,
`quickjs-libc.c`); the single bare definition is in a tcc win32 test never built
here. Filling it is the more useful answer on a shape POSIX does not sanction,
so it stands — but it is a real difference and is written into
`lib/crtl/src/unistd.c` beside the code that causes it.

### Observed in passing, NOT caused by this change

`test/quickjs/runner.c` built from `library_candidates/quickjs` segfaults with
zero output on the full `smoke.js`, and does so **identically when built with
the pinned compiler** — byte-identical (empty) output from both. Small evals
(`print(1+1)`) work on both. Recorded here only so the next person does not
attribute it to the entry stub; it is not a finding of this ticket.

## Log
- 2026-08-20 — resolved, commit 01fbe5ceb.
