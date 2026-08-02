---
track: B
prio: 30
type: feature
---

# crtl gap batch, 2026-08: 10 assumed-libc symbols real C reaches for

- **Type:** feature (libraries) — **Track B** (`lib/crtl`)
- **Filed:** 2026-08-02 under [[feature-crtl-implement-libc-assumptions]], which
  is a standing collector and says "rank the batch you file, not this". This is
  such a batch.

## How it was found — systematically, not by waiting for a corpus to trip

The collector's method is corpus-driven ("implement what the corpus demands"),
which finds gaps only when a project happens to hit them. This batch came from
a **differential probe** instead: 48 commonly-assumed libc symbols, each
compiled by pxx and by gcc, keeping every case gcc accepts and pxx rejects.

38 of 48 already work. The 10 that do not:

| header | symbol | note |
| --- | --- | --- |
| string.h | `strdup` | needs malloc; used by nearly every C program that owns strings |
| string.h | `strndup` | same |
| string.h | `stpcpy` | returns the END pointer — the reason it exists |
| string.h | `memccpy` | |
| string.h | `memrchr` | |
| string.h | `strsep` | the modern `strtok`; mutates through a `char**` |
| string.h | `strcasestr` | GNU, but very widely assumed |
| stdlib.h | `setenv` | see below — NOT just a missing function |
| stdlib.h | `unsetenv` | see below |
| unistd.h | `isatty` | gates "am I on a terminal" output paths everywhere |

All are **library-surface** gaps, so all are Track B per the collector's own
split (a parser gap would be Track C).

## `setenv` / `unsetenv` are not a plain gap — read this first

The Pascal write side landed 2026-08-02 per
[[decide-env-write-side]] (option 3: write to our buffer AND hand that buffer to
`execve`, as one change, so the set-then-spawn case is never silently wrong).

**The C side has a separate buffer.** `lib/crtl/src/stdlib.c` keeps its own
`pxx_env_buf`, loaded independently of the Pascal RTL's. So a C `setenv` writing
to the C buffer would NOT be seen by the Pascal spawn path — reintroducing
exactly the divergence option 3 exists to prevent.

Measured, and it is safe *today*: **crtl exposes no spawn surface at all** — no
`execve`, `fork`, `system` or `posix_spawn` in any crtl header. A pure C program
compiled by pxx cannot start a child, so "write then exec" is unreachable from
C and a C-local write is correct for the only case that exists.

**That is a standing constraint, not a permanent fact.** Whoever adds a spawn
surface to crtl must make it pass crtl's environment — or unify the two buffers
first. Worth a comment at the write site so the next person meets this before
the bug does.

## Shape

Most of the string functions are a few lines each and belong in the header as
static definitions, the way `lib/crtl/include/strings.h` was written on
2026-08-02 — a local definition also has no external name to collide with a
same-named Pascal routine, which is a real hazard here
([[bug-cfront-c-name-binds-to-pascal-routine-at-wrong-arity]]).

`strdup`/`strndup` need `malloc`, so they belong in `stdlib.c` alongside it
rather than in a header. `isatty` needs an `ioctl(TCGETS)` or an `fstat`
character-device check through the PAL.

## Gate

A differential test against gcc per symbol — same file compiled both ways,
outputs diffed, as `test/crtl_libc_oracle.c` already does for the existing
surface. Re-run the probe afterwards and confirm 48/48. Cross-check
i386/aarch64/arm32: `lib/crtl` builds for every target while `gate.sh lib` is
x86-64 only ([[frank2-crtl-changes-need-cross-check]]).
