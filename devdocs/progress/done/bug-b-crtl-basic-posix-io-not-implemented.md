---
summary: "read/write/close/lseek — plus atof, bsearch, rand/srand — were declared by crtl's headers and implemented nowhere; found by probing all 361 declarations for an implementation, not by reading them"
type: bug
track: B
prio: 60
---

# `read`, `write`, `close`, `lseek` were declared and never implemented

- **Type:** bug — Track B (`lib/crtl`), tag `compat`
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** a systematic probe (below), after the same shape turned up twice
  by accident: [[bug-cfront-spurious-dt-needed-libc-with-no-imports]] and
  [[bug-b-crtl-wchar-wctype-declared-not-implemented]].

## The probe, because two accidents are a pattern

Rather than read the headers, **measure**: extract every function prototype from
`lib/crtl/include/**` (361 of them, 27 headers), and for each build a program
that includes only its header and **takes the function's address**. Taking the
address forces a reference without needing valid arguments, so an unimplemented
function shows up as a dynamic import.

    implemented: 343    unimplemented: 18    build-fail: 0

Eighteen. Including the four most basic POSIX calls there are.

Checked for a false positive before believing it: **calling** `write()` produces
the same import, and `src/unistd.c` genuinely had no `write`, `read`, `close` or
`lseek`. They worked only because glibc supplied them — so a program doing raw
file I/O was dynamically linked, and on a target without glibc it simply would
not run.

## Fixed here (8 of the 18)

| function | note |
| --- | --- |
| `read`, `write`, `close`, `lseek` | the `__pxx_read/_write/_close/_seek` bridges already existed in `pxxcio.pas`; this is the PAL's `-errno` mapped to C's `-1` + `errno`, as every other function in `unistd.c` does |
| `atof` | `strtod(s, 0)` — C defines it as exactly that, so not an approximation |
| `bsearch` | qsort's comparator convention; half-open window so the midpoint cannot overflow and an empty range needs no special case |
| `rand`, `srand` | see below |

`RAND_MAX` was also undefined and is now 32767.

### rand deliberately does not match glibc

C does not fix the sequence, so ours is the standard's own example generator,
not glibc's TYPE_3. Copying glibc's would buy a nicer diff and an obligation to
keep a sequence nobody is entitled to rely on. The test therefore asserts only
what C promises — same seed → same sequence, values in `[0, RAND_MAX]`,
`srand(1)` is the initial state — and says why in the file. **A diff-against-gcc
test would fail here for a correct implementation**, which is the trap this note
exists to stop.

## Tests

- `test/cposix_io.c` — whole output diffed against a gcc build. Cases chosen
  where a plausible wrong implementation diverges: `lseek` returns the new
  ABSOLUTE offset (not the delta), `SEEK_END` with a positive offset is legal
  and does not extend the file, `read` at EOF is 0 (not -1), a short read
  returns what it got, and all four set `EBADF` on a closed fd.
- `test/cstdlib_batch3.c` — `atof`/`bsearch` diffed against gcc (hits, both
  boundaries, a gap, and the empty array, which must not be dereferenced);
  `rand` by properties.

Both identical to gcc and statically linked on **x86-64, i386, arm32, aarch64
and riscv32**.

### One trap re-laid and removed

`cposix_io` first differed on arm32/aarch64/riscv32 on a single row — and the
code was fine. The test had written

    printf("close_bad=%d %d\n", close(fd), errno == EBADF);

which reads `errno` and calls `close` **in the same argument list**, where the
evaluation order is unspecified: gcc read `errno` first, pxx-on-arm called
`close` first, and both are correct. Each call is now sequenced before the
`printf` that reports it. That is the third instance this session of the same
mistake, so the reason is written into the test.

## Still unimplemented — 10, all needing PAL work

`poll`, `atexit`, `ioctl`, `chmod`, `umask`, `clock_gettime`, `msync`,
`mremap`, `pread`, `pwrite`. **None has a `__pxx_*` bridge**; `PalPoll` and
`PalIoctl` exist at the PAL level but are not exposed to C, and the rest have no
PAL entry at all. `pread`/`pwrite` specifically should get a real positional
syscall rather than a seek/read/seek emulation, which would be silently
non-atomic. Filed onto the standing collector
[[feature-crtl-implement-libc-assumptions]] rather than faked.

## Gate

`tools/gate.sh lib` GREEN; c-conformance x86-64 and i386 re-run, since crtl
compiles for every target while `lib-test` is x86-64 only. `lib-test` asserts
the linkage of both new tests, because the output diff passes either way on a
glibc host — the blind spot that let all of this sit.
