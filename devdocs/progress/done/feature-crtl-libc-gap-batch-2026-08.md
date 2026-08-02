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

### `isatty` deliberately NOT implemented — and that call was WRONG, see below

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
[[bug-cfront-spurious-dt-needed-libc-with-no-imports]] with the diagnosis
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

## Round 3 (commit 704d4ee20) — asking whether it BEHAVES, not whether it exists

Rounds 1 and 2 asked "does the symbol compile". `strerror` compiled fine and was
a stub, which is the argument for a third round asking whether the answers are
right. Probed printf/snprintf conversion coverage, strtol/strtod edge cases,
qsort/bsearch, ctype over the full byte range, and string comparison signs —
whole output diffed against gcc.

printf/snprintf, qsort/bsearch, ctype and the comparison signs are **clean**.
Three real bugs in the conversion family, all silent-wrong-value:

**1. `strtol`/`strtoul` wrapped instead of clamping.**
`strtol("99999999999999999999", 0, 10)` returned `7766279631452241919` where C
requires `LONG_MAX` and `errno = ERANGE`. `strtoul` was worse: it cast the
SIGNED `strtol` result, so it inherited the wrap and could not represent the top
half of its own range. Base 0 also ignored a leading `0` (octal).

This file's own comment already described the gap — a previous session wrote
`strtoll`/`strtoull` correctly and noted that `strtol` "doesn't clamp on
overflow or auto-detect an octal `0` prefix", reasoning it was masked because
`long` is 64-bit on LP64 and strtol's callers had not reached it. An ordinary
literal reaches it. Both now delegate to the 64-bit pair and clamp; the 64-bit
pair now sets `ERANGE`, which it never did.

**2. `limits.h` defined `LONG_MAX`/`LONG_MIN`/`ULONG_MAX` as the 64-bit values
on EVERY target.** On i386 and arm32, where `long` is 32 bits, the bound was
larger than a `long` can hold: a range check against it could never fire, and
`x == LONG_MAX` was false for a value that really was the maximum. This is why
the clamp from (1) still failed on 32-bit after it was written — the clamp was
right, the constant it compared against was not. Now keyed on
`__SIZEOF_LONG__`, which the frontend predefines correctly per target.

**3. Filed, not fixed:**
[[bug-cfront-arch-predefines-always-x86-64]] — `__x86_64__` is predefined on all
five targets including riscv32, and `__i386__`/`__aarch64__`/`__arm__`/`__riscv`
never are. Track C, urgent: real C selects machine-specific code (including
inline assembly) with these, so a cross-compile takes the x86 branch everywhere,
and the `#else` generic fallback a new target needs is unreachable.

### Two things about the method

The assertions in `test/cstrtol_range.c` are **target-independent booleans**
(`is_LONG_MAX`, not a literal) so one expected output serves 32- and 64-bit
targets. That choice is what exposed bug 2: printing the numbers would have
needed a different expectation per target and hidden the disagreement.

The first version of the probe made **gcc segfault**. It passed `end` to the
same `printf` argument list as the `strtol` call that sets it, and evaluation
order is unspecified, so gcc read an uninitialised pointer. The test was
invalid, not the library — every call is sequenced before its printf now, and
the test says why.

Identical to gcc on x86-64, i386, aarch64 and arm32.

## Round 5 (commit d28b44187) — sscanf's return contract, and two wrong fixes before the right one

Probed sscanf (12 conversion cases) and the math surface (fmod on a negative,
hypot, log2, copysign, floor/ceil/trunc/round on negatives, pow, sqrt, exp, log,
NaN/Inf detection). Math is **entirely clean**. One bug in sscanf:

**`sscanf` returned 0 where C requires EOF.** An input failure *before any
conversion* is -1; 0 means input was available and did not match. Callers depend
on the difference — `while (sscanf(...) != EOF)` terminates on the first and
**spins forever** on the second.

Getting the condition right took three tries, and each wrong one passed the case
that motivated it:

1. *"was the input string empty"* — passes `sscanf("", "%d")`, but misses
   `sscanf("   ", "%d")`. scanf skips leading whitespace before every
   conversion, so a whitespace-only string is an input failure too, and glibc
   returns EOF.
2. *"is the input exhausted where the scan stopped"* — fixes that, and breaks
   `sscanf("abc", "abc")`, which glibc returns **0** for: it consumed its input
   successfully and merely assigned nothing.
3. Correct: *input exhausted after leading whitespace, measured from the
   START*, and only when the format asked for something (`sscanf("", "")` is 0,
   not EOF).

The only reason this converged is that the probe was widened to ten boundary
cases and each diffed against gcc. A test written around the original symptom
would have shipped either wrong version.

Identical to gcc on x86-64, i386, aarch64 and arm32.

## Round 7 (commit 2f23800c7) — the process/user surface, which `getuid` exposed

Sweeping `unistd.h`/`stdlib.h`/`signal.h` after `getuid` turned up missing while
testing `st_uid`. Nine landed: `getuid`, `getgid`, `getegid`, `getppid`,
`pipe`, `kill`, `sleep`, `usleep`, `getpagesize`.

`getuid` is the one worth naming. `geteuid` was present and its siblings were
not, so `if (getuid() == 0)` — the standard "am I root" check — did not compile
at all. Once it does, it must not answer 0 for everyone, which is why the test
asserts the ids are NON-ZERO and that uid matches euid rather than merely that
the call returns.

The costs split three ways, which is why they could land together:

- **No PAL work**: `sleep`/`usleep` over the `nanosleep` crtl already had, and
  `getpagesize`.
- **Bridge only**: `pipe` and `kill` — `PalPipe2` and `PalKill` already existed
  with no `__pxx_` bridge.
- **New PAL surface**: the four id calls, following the pattern used for
  `chdir` earlier the same day. On 32-bit they use the `*32` syscall variants,
  as `PalBackendGeteuid` already did — the legacy 16-bit ones truncate a modern
  uid. ESP reports 0 for all four, honest for a system with one privilege level
  and no process hierarchy.

Verified behaviourally: the pipe must move bytes, and `kill(pid, 0)` must
distinguish a live process from an absent one — a stub returning success passes
a "did it return 0" test and fails this one. Identical to gcc on x86-64, i386,
aarch64 and arm32.

**Documented rather than faked:** `sleep()` returns the seconds REMAINING if
interrupted. The PAL does not surface interruption, so it returns 0 — correct
for every completed sleep, and the comment names the case that is not covered
instead of implying the contract is fully met.

Still missing from that sweep, and deliberately not attempted: `fork`, `execv`
and `alarm`. The first two are process creation, which crtl has no story for at
all (see the note in [[feature-crtl-libc-gap-batch-2026-08]] about the spawn
surface and the environment buffer), and `alarm` needs signal timers.

## isatty, and a correction to round 1

`isatty` landed. Round 1 declined it for two reasons and **both were false**:

- *"crtl has no ioctl bridge (`__pxx_fstat` exists, `__pxx_ioctl` does not)"* —
  `PalIoctl` exists in the PAL (`platform.pas:192`). I had checked for the
  `__pxx_` wrapper and concluded the capability was missing, when only the
  one-line wrapper was.
- *"its true-positive case cannot be verified without a controlling terminal,
  and this build environment has none"* — `/dev/ptmx` **is** a tty and opens
  fine from a non-interactive build, so both directions were testable all along.

The shape of the reasoning was right — do not ship an implementation verified in
only one direction — but it rested on two premises I did not check, and checking
them took about a minute. Recorded here rather than quietly fixed, because the
deferral is written into `unistd.c`'s history and into round 1's notes above.

The implementation is the one round 1 said it should be: the **TCGETS ioctl**,
not `fstat` + `S_ISCHR`. `/dev/null` is a character device and is not a tty, so
the fstat version answers 1 for redirected output and every "am I interactive"
branch takes the wrong path. `test/cisatty.c` checks `/dev/null` and a directory
alongside a real terminal for exactly that reason — a one-sided test would pass
against the wrong implementation.

TCGETS is `0x5401` on every target pxx builds for (asm-generic; only
mips/alpha/sparc/powerpc differ). Identical to gcc on x86-64, i386, aarch64 and
arm32.

## Both probes are now at zero gaps

`48/48` and `60/60`, from `38/48` and `55/60` when the sweeps started. Across
the rounds: 21 functions implemented, and eight bugs found — five in the library
(`strerror` stub, `strtol` overflow wrap, `limits.h` widths, `sscanf` EOF,
`struct stat`'s hardcoded fields) and three in the compiler, filed to Track C
([[bug-cfront-plain-char-is-unsigned-and-folds-inconsistently]],
[[bug-cfront-sizeof-unparenthesised-subscript]],
[[bug-cfront-spurious-dt-needed-libc-with-no-imports]]).

Still absent by decision, not oversight: `fork`, `execv`, `alarm`.
