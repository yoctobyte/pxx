# crtl — pxx's own C runtime

`lib/crtl` is the libc-free C runtime that pxx links into C programs by default.
It is **not** a hosted libc clone and does not aim to be one: it covers what the
C corpora and regression tests actually need, project-owned, with no host libc
underneath.

- `include/` — project-owned headers, auto-registered on the default `<>` search
  path, so `#include <math.h>` resolves here rather than `/usr/include`.
- `src/` — the matching implementations. Real code, not stubs.

## How it gets linked

There is no separate link step: pxx compiles a C program source → executable in
one shot, so the compiler decides where a called C function comes from. When a
crtl header resolves, the preprocessor **also pulls its sibling `src/<name>.c`**.
`#include <math.h>` alone is therefore enough to get the implementation, and the
binary has no `DT_NEEDED` at all.

`--system-libs` opts out and links the host's real shared libraries instead.
Full mechanism, including the per-symbol and per-library granular forms:
**`devdocs/dev/c-linking-and-crtl-autopull.md`**.

## What is here

Headers for roughly thirty of the standard set (`stdio`, `stdlib`, `string`,
`math`, `time`, `signal`, `setjmp`, `pthread`, `wchar`, `inttypes`, the `sys/`
and `netinet/` groups, …), with seventeen implementation files behind them.

`src/math.c` is the substantial one: ~114 functions on correctly-rounded
double-double kernels. It is **deliberately not glibc-bit-compatible** — where
glibc is not correctly rounded, crtl stays correctly rounded rather than
reproducing glibc's error (`decide-crtl-libm-glibc-bit-parity`, 2026-07-20).
Describe it as *"correctly rounded, judged against high-precision references"* —
never as *"matches glibc"*, which is both false and self-defeating.

## crtl's math is NOT the Pascal RTL's math

`lib/crtl/src/math.c` and `lib/rtl/math.pas` are two independent libraries, on
purpose. `Round(2.5)` is 2 in Pascal (banker's) and `round(2.5)` is 3 in C
(half away from zero); both are correct for their language, and no single
implementation can serve both. C reaching into Pascal's math was tried and it
silently broke C programs.

Read **`devdocs/dev/math-implemented-twice.md`** before "de-duplicating"
anything here.

## Adding to it

Add declarations and implementations when a corpus target or regression test
needs them. Keep them simple and project-owned; **do not copy host libc sources
into this tree.**
