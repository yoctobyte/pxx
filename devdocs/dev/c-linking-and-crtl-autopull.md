# C linking model: crtl auto-pull (the "magic link")

pxx compiles a C program in **one shot** — source → executable. There is no
separate link step a Makefile would run afterward. So the compiler itself has to
decide where a called C library function (`fabs`, `printf`, `memcpy`, …) comes
from. Two sources:

1. **pxx's own libc-free C runtime, `lib/crtl/`** — the default.
2. **Real system shared libraries** (`libc.so.6`, `libm.so.6`) via `DT_NEEDED` —
   opt-in.

## Default: auto-pull the libc-free crtl impl

`lib/crtl/` is split the normal C way:

- `lib/crtl/include/<name>.h` — **declarations** (`extern double fabs(double);`).
  Auto-registered on the default `<>` search path (`AddDefaultCIncludeDirs`), so
  `#include <math.h>` resolves here, not `/usr/include`.
- `lib/crtl/src/<name>.c` — the **implementation**, libc-free. Either a real
  body, or a thin bridge to the Pascal RTL (e.g. `math.c`'s `sqrt`/`sin`/`pow`
  bind case-insensitively to `lib/rtl/math.pas`'s `Sqrt`/`Sin`; `fabs`/`frexp`
  are inline).

**The mechanism (cpreproc.inc):** when a crtl `<header>` resolves, the
preprocessor *also* pulls its sibling `src/<name>.c` — `CPAutoPullCrtlImpl`,
right after the header is processed in `CPInclude`. That is the missing link
step: `#include <math.h>` alone (no `-I`, no unity include) makes `fabs` resolve
to the bridged body, and the binary has **no `DT_NEEDED`** at all.

Each impl is pulled **at most once** per compile (`CrtlSrcPulled` dedup). The
dedup also covers an explicit `#include "math.c"` (a unity build like
`test/lua/runner.c`): the explicit include registers the path, so the later
`<math.h>` auto-pull skips it — no double-definition. It likewise breaks the
cycle where `math.c` itself `#include <math.h>` (which would otherwise re-pull
`math.c`).

A crtl header with **no** sibling `.c` (pure declarations / macros, e.g.
`stddef.h`) auto-pulls nothing — the absent file just no-ops.

## Opt-in: real system shared libraries

`--system-libs` turns the auto-pull off for the whole program. Then a crtl
header's `extern` declarations resolve the normal way — as dynamic symbols with
a `DT_NEEDED` (`libm.so.6` for the math names classified in
`ParseCSubroutine`, else `libc.so.6`). Use this to link a C program against the
host's real libraries instead of pxx's bundled runtime.

Per-symbol opt-in is also possible with an explicit `external 'soname'` clause on
a declaration (the general external-symbol path), independent of the crtl set.

## Adding a crtl function

1. Declare it in `lib/crtl/include/<name>.h`.
2. Implement it libc-free in `lib/crtl/src/<name>.c` (a real body, or bridge to a
   `lib/rtl/*.pas` routine — watch the case-insensitive C↔Pascal `FindProc`
   binding: a same-name wrapper `double sqrt(double x){return Sqrt(x);}` recurses,
   so let matching names bind directly and only wrap the name-mismatch cases).
3. Any C program that `#include <name.h>` now gets it, libc-free, automatically.

These files are **Track B** (`lib/crtl/**`). The auto-pull mechanism itself lives
in the compiler (`cpreproc.inc`, Track C).

## Status / limits

- Trigger is "header include pulls the impl"; unused functions in a pulled `.c`
  are removed from the binary by dead-code elimination, so a pulled-but-unused
  module costs compile time only, not binary size. (A future refinement could
  skip compiling a module whose symbols are never referenced.)
- `--system-libs` is a whole-program switch. Mixing — most functions from crtl,
  one from a real `.so` — is done per-symbol via an explicit `external 'soname'`.
