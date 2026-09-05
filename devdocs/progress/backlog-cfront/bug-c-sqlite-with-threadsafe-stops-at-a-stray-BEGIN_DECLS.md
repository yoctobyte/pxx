---
slug: bug-c-sqlite-with-threadsafe-stops-at-a-stray-BEGIN_DECLS
track: C
type: bug
prio: 30
status: open
found: 2026-09-05
found-by: frankC
owner: ""
blocked-by: []
summary: "BARE OBSERVATION, CAUSE UNKNOWN AND DELIBERATELY NOT GUESSED. `./compiler/pascal26 --threadsafe library_candidates/sqlite/sqlite3.c` stops with `stray token at top level (not a declaration): '__BEGIN_DECLS'`, rc=1. PRE-EXISTING, not caused by ec1a1d7b6 -- verified by stashing that change, rebuilding, and getting the identical failure, so `is this mine' is already answered and nobody needs to repeat the rebuild. NOT REDUCED: `--threadsafe' alone builds and runs a trivial program, and `#include <pthread.h>' plus `--threadsafe' builds too, so the minimal repro is still the whole amalgamation. `__BEGIN_DECLS' does not appear anywhere in lib/crtl/include; it is a glibc sys/cdefs.h macro and /usr/include/pthread.h uses it once -- which is an observation about where the token lives, NOT a claim about how it was reached. The amalgamation is otherwise healthy: --emit-obj -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION compiles it clean at 4458 procs."
---

# sqlite with `--threadsafe` stops at a stray `__BEGIN_DECLS`

Filed as an **observation with its aperture**, not a diagnosis. Everything
below was measured today at fixedpoint `b713783d40d8`; nothing below proposes a
mechanism, on purpose.

## What happens

```
$ ./compiler/pascal26 --threadsafe library_candidates/sqlite/sqlite3.c OUT
pascal26:52: error: stray token at top level (not a declaration): '__BEGIN_DECLS'
  near:       >>> __BEGIN_DECLS extern
rc=1
```

## What is already ruled out, so nobody repeats it

| probe | result |
| --- | --- |
| same command with `ec1a1d7b6` **stashed** and rebuilt | **identical failure** — pre-existing |
| `--threadsafe` on a trivial `printf` program | builds **and runs** |
| `--threadsafe` on `#include <pthread.h>` + empty `main` | **builds** |
| `--threadsafe` on `<stdio.h>` + `<pthread.h>` + empty `main` | **builds** |
| `--emit-obj -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION` | **compiles clean**, 4458 procs |

So it is not the flag on its own, not `<pthread.h>` on its own, not this
week's static-alias change, and not the amalgamation as such.

## One fact about the token, offered as a fact

`__BEGIN_DECLS` appears **nowhere** in `lib/crtl/include`. It is a glibc
`sys/cdefs.h` macro, and `/usr/include/pthread.h` contains exactly one
occurrence.

**That locates the string. It does not establish that the system header was
reached, nor how**, and the difference matters: the obvious story — "the system
`pthread.h` got in instead of crtl's" — is exactly the plausible cause this
ticket is written to avoid asserting. The reduction probes above went looking
for it and did **not** reproduce, which is evidence against the easy version of
that story rather than for it.

## Why it is filed without a cause

Reducing it further needs someone to sit with the preprocessor, and a ticket
that guesses gets the guess quoted back as though it were measured. The value
here is the negative results: **the aperture is recorded, the "is this mine"
question is answered, and the cheap reductions are known not to reproduce.**
Whoever takes it starts after those, not before them.

## Rank

p30. Nothing in tree depends on a threadsafe sqlite today, and the amalgamation
compiles by the route anything would actually use. It is filed because
`--threadsafe` is a supported flag and this is a real, reproducible refusal on
the largest C corpus we have.
