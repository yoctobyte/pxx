---
slug: regression-test-zlib-conflicting-typedef-gz-statep
title: "test-zlib died on `conflicting types for typedef 'gz_statep'` — the compiler was right and the runner was invalid C"
track: A
prio: 70
type: regression
status: done
owner: frankH
---

# summary

`test-zlib` failed compiling its unity runner with
`pascal26:202: error: conflicting types for typedef 'gz_statep'`.
**gcc rejects the same file with the same error on the same line**, so the
diagnostic was correct and `test/zlib/runner.c` has been invalid C all along —
the redefinition check added 2026-09-05 (`97788cf59`) merely started saying so.
Fixed in the test by giving the struct a tag, which is what makes a repeated
typedef legal. No compiler change.

# What it was

`gzguts.h` typedefs an **anonymous** struct and has **no include guard**:

```c
typedef struct { ... } gz_state;
typedef gz_state FAR *gz_statep;
```

**Five** files in the unity build include it — the four `gz*.c`, plus
`zutil.c`, which spells it `#  include "gzguts.h"` with spaces and is therefore
missed by a grep for `#include "gzguts.h"`. Real zlib compiles each `.c`
separately and never sees the repeat; our runner is a single translation unit,
so the typedef is parsed five times. An anonymous struct has no tag to dedupe
on, so **each pass is a distinct type in C** and the repetition is invalid.

| | verdict |
| --- | --- |
| pxx on `runner.c` | `pascal26:202: conflicting types for typedef 'gz_statep'` |
| gcc on `runner.c` | `gzguts.h:202:23: error: conflicting types for 'gz_statep'` |
| gcc on the zlib-only unity TU, untagged | REJECTED, 13 conflicting-type errors |
| gcc on the same TU, tagged | ACCEPTED |

Measured boundary — the pointer is not the trigger:

```
typedef struct { int m; } S;  typedef S *SP;      REFUSED   (the zlib shape)
typedef struct { int m; } S;  typedef S SS;       REFUSED   (no pointer)
struct stag { int m; }; typedef struct stag *P;   ok        (tag dedupes)
typedef int *IP;                                  ok        (no record)
typedef struct { int m; } S;                      ok        (the aggregate
                                                   typedef itself — why this
                                                   went unnoticed)
```

# The fix, and the two wrong ones I tried first

**Landed:** the recipe copies `gzguts.h` with `sed` inserting a tag
(`typedef struct pxx_gz_state_s {`) plus the five includers into
`$(TESTTMP)/zlibtag`, and puts that dir first on `-I`. A quoted include searches
the includer's own directory before `-I` (measured, gcc and pxx alike), so the
`.c` files must sit beside the tagged header. Everything else still resolves out
of `$(ZLIB_SRC)`. The `sed` is asserted and **branched on** — an unbranched
assertion in a `;`-chained recipe is a comment.

**Wrong fix 1 — relaxing the compiler check.** I added `CRecSameShape` to
`cparser.inc` so a repeated typedef compares record SHAPE rather than id. It
made the runner compile and kept all five genuine-conflict controls red,
including the `time_t` case the check was built for. **It is still wrong**: it
buys a green row by accepting what the very oracle this test diffs its output
against refuses. Reverted.

*How I got there:* my probe printed `gcc: accepted` from
`gcc ... 2>&1 | tail -3 && echo "gcc: accepted"` — the `&&` branches on `tail`,
which always succeeds. **The instrument reported success unconditionally and I
built a compiler change on it.** CLAUDE.md names this exact shape ("branch on
the assert"); I wrote it into a probe anyway.

**Wrong fix 2 — an include guard on the header.** The obvious move, and it does
stop the redefinition. It breaks the runner's existing `#undef COPY` workaround,
which *depends* on `gzguts.h` being re-included to restore `COPY` after
`inflate.h`'s enum constant of the same name has been parsed. Measured:
`gzread.c` then fails on `state->how == COPY` with `expected C expression`.
The tag has no such interaction — `COPY` is redefined every pass exactly as
before.

# Instrument notes

- **`grep -n '#include' zutil.c | head` hid the fourth includer.** `head`
  truncated before line 116, and the `#  include` spelling would have escaped
  the pattern anyway. runner.c's own comment said zutil.c pulls `gzguts.h` and
  it was right; I contradicted it from a truncated grep.
- **A stale binary produced a false PASS.** After a failed compile the diff ran
  against the previous run's `pxx_zlib_runner` and printed
  `byte-identical to gcc oracle`. The compile error was on screen at the time.
  The recipe's own `|| exit 1` prevents this in the real target; my hand-run
  reproduction had no such branch.
- **gcc rejecting `runner.c` under `-Ilib/crtl` proves nothing about zlib** —
  the errors are all in our libc replacement, which gcc was never meant to
  compile. The zlib-only TU is the probe that answers the question.

Resolves the `test-zlib#src:tools/compiler_srchash.sh` row, which is a job
NAMING artefact (testmgr names a job after its first source); the srchash guard
passed and the job died later.
