# Handover - 2026-06-28 Track A+B+C cleanup

Paste this into a fresh session if you need to resume from the current head.

---

You are on `master` in `frankonpiler`. The tree should be clean and pushed.

Current head:

```text
2a473bda fix(bootstrap): restore FPC seed build
695b0cad chore(stable): pin v84
5b581e7b fix(cfront): unblock sqlite aggregate smoke
```

`origin/master` is expected to match local `master`.

## What landed

### SQLite / C frontend cleanup

Commit `5b581e7b` fixed the SQLite aggregate crash. The original
`VdbeCursor`/bitfield diagnosis was false: direct layout probes showed PXX and
GCC agree on the full SQLite `VdbeCursor` layout. The real bug was in
`ParseCStructInto`: inline nested aggregate pointer fields like
`struct AggInfo_func { ... } *aFunc;` skipped the `*aFunc` member, so field
lookup fell through to offset 0 and aggregate queries crashed.

Fix:
- `compiler/cparser.inc` now parses stars in the inline nested aggregate branch.
- Pointer-to-nested-record metadata is recorded for single-star members.
- Guard: `test/cinline_struct_ptr_field_b129.c`.
- `test/csqlite_extended_test.c` was manually verified through
  `CREATE/INSERT/SELECT/UPDATE/DELETE/COUNT/SUM/AVG/close`.

### CRTL string leaves

`lib/crtl/src/string.c` now has simple declared string helpers:
`strrchr`, `memchr`, `strcat`, `strncat`, `strspn`, `strcspn`, `strpbrk`,
`strstr`, `strcoll`, `strxfrm`, `strerror`.

Guard: `test/crtl_string_leaf_b130.c`.

After this, the SQLite extended unity binary no longer imports CRTL string
helpers. Remaining dynamic imports are OS/VFS calls:

```text
fchmod fcntl64 fstat64 fsync getpid gettimeofday localtime lstat64 mkdir
mmap64 munmap nanosleep open64 stat64 sysconf utimes
```

Those remain tracked by
`devdocs/progress/backlog/task-sqlite-libc-free-runtime-bringup.md`.

### Devdocs / progress cleanup

Added compiler-test candidate docs:
- `devdocs/developer/game-library-candidates.md`
- `devdocs/developer/pascal-torture-candidates.md`
- `devdocs/developer/c-torture-candidates.md`
- `devdocs/progress/backlog/feature-game-library-candidate-suite.md`

Progress ticket moves:
- `bug-c-sqlite-sql-exec-schema-parse-corrupt` -> `done/`
- `bugfix-cfront-sqlite3-crash-vdbecursor-layout` -> `done/`
- `bugfix-cfront-bitfield-packing-gcc-compat` -> `rejected/`
- `feature-random-library` -> `backlog/`

The board was regenerated and `tools/progress.sh check` passes with only
historical hygiene warnings.

### Stable pin

Commit `695b0cad` pinned stable v84:

```text
stable v84 sha:
12d5149f4718b5b066d786da8163361bd7c9a7e25e211d12af02c7c00ef2070d

pinned source commit:
5b581e7b fix(cfront): unblock sqlite aggregate smoke
```

Important: v84 pins `5b581e7b`, not current head. The later bootstrap fix
`2a473bda` is source hygiene only; the produced compiler binary stayed
byte-identical in checks. Re-pin only if you specifically want the stable
metadata to point at the FPC-forward fix too.

### FPC bootstrap hygiene

After the v84 pin, `make test-fpc` initially failed under real FPC 3.2.2 with
declaration-order errors:
- missing FPC-visible forwards for `IRLowerAddress`, `IRNodePointerBase`,
  `IRPointerStride`
- duplicate `ParseCCommaExpr` forward
- missing local forwards for `CBraceTopLevelInitCountAt` and `CSkipCInitElement`

Commit `2a473bda` fixes only that ordering/hygiene:
- `compiler/forwards.inc`
- `compiler/cparser.inc`

## Verified

Before the pin:

```sh
make test-core
make lib-test
tools/progress.sh check
git diff --check
```

Pin:

```sh
make stabilize
make pin
make pxx-stable-check
```

After the FPC hygiene fix:

```sh
make test-fpc
./compiler/pascal26 -dPXX_REQUIRE_FORWARD compiler/compiler.pas /tmp/pascal26-require-forward
/tmp/pascal26-require-forward test/hello.pas /tmp/hello-require-forward
git diff --check
```

All passed. `make test-fpc` includes `fpc-check` and asm emit oracle checks for
x64, 386, rv32, a64, and arm32.

## Current board top

As of the last board regeneration:

```text
urgent: 0
working: 0
unfinished: 5
blocked: 1
backlog: 76
rainy-day: 19
done-followup: 5
done: 346
```

Unfinished:
- `feature-c-desktop-lua-sqlite-path`
- `feature-eliah-ide`
- `feature-eliah-m0-window`
- `feature-eliah-m1-designer`
- `feature-eliah-pane-collapse`

Blocked:
- `feature-c-runtime-library`, blocked by `feature-c-source-frontend`

## Suggested next moves

1. If Track B wants the newest C fixes, it can now use pinned v84.
2. For SQLite libc-free runtime, continue with the OS/VFS bridge or a reduced
   in-memory VFS; string helpers are no longer the blocker.
3. For compiler testing candidates, start with smaller candidates before the
   heavy suites:
   - C: `zlib`, `SQLite`, `Lua`, `stb`, `sokol`
   - Pascal: `TRegExpr`, `DCPcrypt`, `BGRABitmap`, `PascalScript`
   - Game libs: `raylib`, `Orx`, `Castle Game Engine`, `ZenGL`
4. Do not resurrect the VdbeCursor bitfield ticket unless a new independent
   layout mismatch is found; that diagnosis was explicitly rejected.

## Quick sanity commands

```sh
git status --short --branch
git log --oneline --decorate -5
tools/progress.sh check
make pxx-stable-check
```

Expected status:

```text
## master...origin/master
```

