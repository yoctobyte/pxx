# C runtime/library layer (`lib/crtl`) plus direct C-library packages

- **Type:** feature (C frontend / RTL — legitimately Track B library work
  originally; reassigned to C now that C owns `lib/crtl` and the C runtime)
- **Status:** blocked
- **Track:** C (C frontend)
- **Owner:** — (lock released; last worked by Codex)
- **Opened:** 2026-06-20
- **Blocked-by:** feature-c-source-frontend
- **Relation:** supports `feature-c-source-frontend`,
  `feature-c-regex-library-devtest`, and future C-source candidates such as INI,
  PNG, zlib, and embedded utility libraries.

## Goal

Build a small, platonic C runtime/library layer for source-backed C libraries:
the expected C headers and minimal implementations that candidate C libraries
need, without pulling in host glibc/clang headers and without pretending to be a
complete hosted libc.

This is Track B work: write the desired C library surface cleanly. Do **not**
distort it around current compiler limitations. When the C frontend cannot
compile the intended source, file Track A compiler tickets.

## Proposed layout

```text
lib/
  crtl/
    include/
      stddef.h
      stdint.h
      stdbool.h
      limits.h
      string.h
      ctype.h
      stdlib.h
      stdio.h
      errno.h
      signal.h
      setjmp.h
    src/
      string.c
      ctype.c
      stdlib.c
      stdio.c

  clib/
    <package>/
      package metadata
      include/
      src/
```

`lib/crtl` is the C compatibility substrate. Larger source-backed C libraries
like regex, zlib, PNG, INI, etc. should get their own package folders, not be
mixed into `lib/crtl/src`.

## Scope policy

- Implement opportunistically: add functions/types/macros when real candidate
  libraries or tests need them.
- Prefer simple, portable, boring C over clever libc tricks.
- Use existing PXX builtin/RTL/platform facilities underneath where appropriate.
- Keep hosted features honest: environment and signals are valid long-term
  runtime features, but target behavior may differ between Linux and ESP32.
- Defer `setjmp`/`longjmp` until a real candidate needs them; they are nonlocal
  stack/register jumps, not ordinary `goto`, and interact with cleanup/managed
  values.
- Avoid vendoring clang/glibc headers as a shortcut.

## Naming / import design still open

Direct Pascal import of C packages is required; Pascal wrappers must be optional.
For example, a user should be able to import zlib's C API without a Pascal
wrapper, while a later Pascal-friendly `zlib.pas` wrapper can coexist.

Do **not** settle the namespace here. Known problem:

- `uses zlib` as a Pascal wrapper and `uses zlib` as a direct C package collide.
- Explicit forms like `uses c/zlib` are clear but not Pascal-compatible syntax.
- Header-file-shaped imports like `uses zlib.h` may bind the language surface to
  filenames rather than packages.

This needs a deliberate compiler/library namespace decision before accepted
`lib/clib` packages become a public surface.

## Acceptance

- `lib/crtl/include` provides the small C header set needed by early candidate
  libraries.
- `lib/crtl/src` implements the actually used basics (`memcpy`, `strlen`,
  `strcmp`, `malloc`/`free` hooks, `ctype` ASCII helpers, small `stdio` pieces,
  etc.) as demand appears.
- Candidate C libraries can include local/project headers before system
  fallbacks.
- Missing compiler support discovered while compiling this layer is captured as
  Track A tickets, not worked around silently.

## Log
- 2026-06-20 — Opened from regex/INI candidate discussion. Project direction:
  Pascal/builtin/RTL remains the base; C runtime headers/source are wrappers or
  thin implementations over that base; larger C libraries live beside `crtl` as
  separate packages. Import naming intentionally deferred.

## Log
- 2026-06-20 — Unblocked on the search-path side: `-I<dir>` now adds project
  include roots that resolve before host `/usr/include` (which is native-only
  now), so a `lib/crtl/include` root can shadow host headers and stay
  cross-platform. The remaining work here (the `crtl` header set + `src`
  implementations, package layout, import-namespace decision) is Track B and
  intentionally NOT started — file Track A tickets for any compiler gap hit while
  compiling the layer. Per-directory manifest auto-application (so `lib/crtl`
  becomes an include root without a CLI `-I`) is tracked in
  feature-dynamic-include-paths-config.
- 2026-06-20 — Claimed for Track B C interop slice. Added the first
  project-owned `lib/crtl/include` surface (`stddef`, `stdint`, `stdbool`,
  `limits`, `string`, `ctype`, `stdlib`, `stdio`, `errno`, `signal`, `setjmp`,
  `assert`, plus tiny `sys/cdefs.h` / `sys/_types.h`) and empty `src/`
  staging. Added `test/crtl_header_smoke.c` and `make c-interop-devtest`.
  Pinned v17 compiles and runs the header smoke (`crtl-headers-ok`).
- 2026-06-20 — Extended the owned header surface for the FreeBSD regex source
  include set: `sys/types.h`, `wchar.h`, `wctype.h`, `unistd.h`, plus small
  constants / typedefs needed by those headers. Added a `freebsd_regex_regerror`
  devtest probe; it now gets past project headers and reports a C-body frontend
  gap instead of an include gap.
- 2026-06-21 — Added `fprintf` to `stdio.h` and `reallocarray` to `stdlib.h`
  for FreeBSD regex / tiny-regex-c candidate pressure. Added first
  `lib/crtl/src/` implementations: `string.c` (memcpy/memmove/memset/memcmp/
  strlen/strcmp/strncmp/strcpy/strncpy/strchr) and `ctype.c` (ASCII lookup
  table). Added `test/crtl_src_probe.c` to `make c-interop-devtest`; it reports
  `GAP crtl_src_probe -- undefined variable (strlen)`, confirming the C body
  frontend (Track A `feature-c-source-frontend`) is the remaining blocker for
  compiling the runtime source. Ticket now `Blocked-by: feature-c-source-frontend`.

- 2026-06-21 — HALTED → `unfinished/`. `working/` lock released (no active agent). No uncommitted code this round; parked pending the C source frontend (feature-c-source-frontend, Track A).
- 2026-06-22 — State audit on Track B: moved `unfinished/` → `blocked/`
  because this ticket's remaining acceptance requires
  `feature-c-source-frontend` (Track A). No Track B code change needed.
