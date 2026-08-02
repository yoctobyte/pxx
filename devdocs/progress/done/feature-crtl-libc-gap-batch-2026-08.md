---
track: B
prio: 30
type: feature
status: done
owner: claude-B
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

## Landed 2026-08-02 (commit 37928b45b) — 9 of 10

The probe now reports **47 of 48**. Implemented: `stpcpy`, `memccpy`,
`memrchr`, `strsep`, `strcasestr` (in `lib/crtl/src/string.c`), `strdup`,
`strndup`, `setenv`, `unsetenv` (in `stdlib.c`, where `malloc` and the
environment buffer already live).

### `isatty` deliberately NOT implemented

The obvious implementation is `fstat` + `S_ISCHR`, and it is **wrong**:
`/dev/null` is a character device and is not a tty. Confirmed against gcc,
which answers `isatty` on an open `/dev/null` as **0**. Shipping the `fstat`
version would make every "am I on a terminal" branch — colour, progress bars,
prompting — take the interactive path whenever output is redirected to
`/dev/null`.

The correct implementation is the `TCGETS` ioctl, which succeeds only on a tty.
crtl has no ioctl bridge (`__pxx_fstat` exists, `__pxx_ioctl` does not). Adding
one is small, but its **true-positive** case cannot be verified without a
controlling terminal, and this build environment has none — so it would land
tested only in the negative direction. Left out, with the reasoning recorded at
the site in `unistd.c` so the next person meets it before the bug does.

### Verified behaviourally, against gcc, not by compiling

`test/cstring_batch.c` diffs its **whole output** against the same file built by
gcc, so there are no recorded expectations to drift. The cases are chosen where
each function differs from its obvious cousin, since that is where a plausible
wrong implementation hides: `stpcpy` returning the NUL rather than the start
(and chaining on it), `memccpy` stopping *after* the byte and yielding NULL when
absent, `memrchr` with `n = 0` not reading at all, `strsep` producing an EMPTY
token between adjacent delimiters where `strtok` skips it, `strndup`
NUL-terminating a truncated copy, and `setenv(..., overwrite = 0)` NOT replacing
an existing value.

**Identical to gcc on x86-64, i386, aarch64 and arm32.** The cross-target run is
not optional here — `lib/crtl` builds for every target while `gate.sh lib` is
x86-64 only ([[frank2-crtl-changes-need-cross-check]]).

### The setenv hazard, as filed

Records are appended rather than edited in place (a longer replacement value
would have to shift the rest of a fixed 16K buffer), and a superseded record is
hidden by making its name unmatchable with a `\1` first byte — a byte no
environment name can contain — which preserves the NUL-separated record
structure `getenv`'s scan walks. Blanking the record instead would have made the
scan treat it as an empty record and mis-step.

The standing constraint about crtl's buffer being separate from the Pascal spawn
path's is recorded in a comment at the definition, not only in this ticket.

## Log
- 2026-08-02 — resolved, commit PENDING.

## Round 2 (commit c224672a1) — a second probe, and a stub that made round 1 useless

Ran the same differential over 60 symbols in headers round 1 did not cover
(dirent, sys/mman, sys/wait, sys/socket, netinet, poll, pthread, locale, wchar,
math, more stdio/stdlib/string). 55 already worked. Fixed:

- **`strerror` was a STUB** — it ignored `errnum` and returned the literal
  `"error"` for every value. That made `perror` and `strerror_r`, which round 1
  had just added, report nothing useful: *"cannot open config: error"*. Now the
  real table, **generated from gcc rather than transcribed**, including the two
  indices where glibc has no name and falls through to `"Unknown error N"`.
  Identical to gcc across 0..140 and negatives.
- **`perror`** and **`strerror_r`** (the XSI form — returns int, not GNU's
  `char*`; the two disagree on the return type and code testing the result as an
  int is the common case).
- **`htons`/`ntohs`/`htonl`/`ntohl` reachable from `<netinet/in.h>`.** They were
  implemented and declared only in `<arpa/inet.h>`; glibc declares them in both,
  and network code routinely includes only `<netinet/in.h>`.

The probe now reports **59 of 60** and **47 of 48**. The two left are `chdir`
(needs a PAL bridge that does not exist — `__pxx_chdir` is absent) and `isatty`
(above).

### A pre-existing defect this surfaced, filed not fixed

Calling `htons` — a pure byte-swap — makes the binary `NEEDED libc.so.6` on
every target, losing the libc-free property the opt-in `-dPXX_DYNLIB_LIBC`
design rests on. Verified to happen through the OLD `<arpa/inet.h>` path too, so
it is not from this change. Filed as
[[bug-b-crtl-htons-pulls-libc-into-a-static-binary]] with the diagnosis
explicitly left open, because `socket.c` declares only `__pxx_*` Pascal-side
externs and it is not obvious why they force a libc dependency.

It is also why `test/cerrno_strings.c` does not exercise the byte-order helpers:
including them made the binary dynamic, which made it unrunnable under qemu
without a target sysroot — so the `strerror` table, the substantial fix, would
have been verifiable on x86-64 only. Header visibility is what changed here and
the compile-time probe covers it.

Verified: both streams (stdout and stderr separately, since `perror` writes to
stderr and a merged stream compares buffering rather than content) identical to
gcc on **x86-64, i386, aarch64 and arm32**.
