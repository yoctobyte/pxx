---
prio: 64  # auto
---

# sqlite libc-free runtime: pull crtl math/string + the OS/VFS bridge

- **Type:** task (libc-free runtime bring-up) — Track B (`lib/crtl/**`) +
  harness; the compiler/lowering side is done.
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the preprocessor-arithmetic fix
  ([[bug-c-sqlite-undefined-symbol-memsetdefault]]) let `sqlite3_open` run.

## Direction (per user, 2026-06-27)

**Do NOT pull libc/libm for math (or anything else).** Math is provided
libc-free already: `lib/crtl/src/math.c` implements `fabs`/`frexp`/`ldexp`/`modf`
and bridges `sqrt`/`sin`/`pow`/… to the Pascal RTL `lib/rtl/math.pas`. The only
reason a standalone `sqlite3.c` compile reported `undefined symbol: fabs` is that
the driver did not unity-include the crtl source — so `fabs` fell to the
`<math.h>` extern (libm) path, and libm then never gets a `DT_NEEDED` anyway.

Verified: a driver that does
```c
#include "math.c"
int main(){ return (int)(fabs(-3.5) + sqrt(16.0)); }   /* -> 7 */
```
with `-Ilib/crtl/include -Ilib/crtl/src` links with **zero NEEDED libraries**
(fully libc-free) and runs correctly. So math is DONE; the lua runner already
uses this unity-include pattern (`test/lua/runner.c` `#include "math.c"`).

## Remaining work (the real bring-up)

A libc-free sqlite driver `#include`-ing `sqlite3.c` plus the crtl srcs compiles,
but its dynamic-symbol table still shows the sqlite OS-interface dependencies
(`nm -D`):

- **string:** done 2026-06-28. `lib/crtl/src/string.c` now provides the declared
  leaf helpers SQLite was importing (`memchr`, `strcspn`, `strrchr`, `strspn`,
  `strerror`) plus the rest of the simple declared string helpers. Guard:
  `test/crtl_string_leaf_b130.c`.
- **OS / VFS (the big piece, needs a PAL/syscall bridge):** `open64 read write
  close fstat64 lstat64 stat64 fcntl64 fchmod mkdir utimes mmap64 munmap fsync
  getpid gettimeofday nanosleep sysconf localtime` — sqlite's `os_unix.c` raw
  syscall surface.
- **threads:** keep current bring-up on `SQLITE_THREADSAFE=0`. A later
  multithreaded SQLite path needs the constrained syscall-only pthread subset
  tracked in [[feature-syscall-pthread-shim]].
- **dl:** `dlopen/dlclose/dlsym/dlerror` — `SQLITE_OMIT_LOAD_EXTENSION` defers it.

The current unity driver can now run a rich in-memory SQLite smoke when it is
allowed to import libc for the OS/VFS calls. Full libc-free status still requires
the OS/VFS bridge or a deliberately reduced in-memory VFS configuration.

## 2026-06-28 update

The compiler-side blockers immediately in front of SQLite init are cleared:

- block-scope `static const sqlite3_mem_methods defaultMethods = { fn, ... }`
  now materialises function-pointer fields correctly;
- block-scope `static sqlite3_vfs aVfs[] = { ... }` now has persistent storage,
  inferred record-array length, and populated fields;
- `sizeof(recordArray)/sizeof(recordArray[0])` now returns the correct count.

With the current unity driver, `sqlite3_initialize()` registers the `unix` VFS,
`sqlite3MemdbInit()` succeeds, and `sqlite3_open(":memory:")` followed by
`sqlite3_close()` exits 0.

The first SQL execution no longer crashes in the schema error path; that pointer
truncation is fixed in [[bug-c-sqlite-sql-exec-schema-argv-pointer]]. The next
wall is a clean `SQLITE_CORRUPT` return while preparing SQLite's built-in
`sqlite_master` schema SQL, tracked as
[[bug-c-sqlite-sql-exec-schema-parse-corrupt]].

## 2026-06-28 update 2

The schema execution wall is cleared. `test/csqlite_schema_exec_probe.c` reports
`open=0`, `exec=0`, `close=0`, and `test/csqlite_extended_test.c` runs through a
larger in-memory workflow including aggregate queries.

`nm -D /tmp/pxx_csqlite_extended` no longer lists the CRTL string helpers. The
remaining dynamic imports are OS/VFS calls:

```text
fchmod fcntl64 fstat64 fsync getpid gettimeofday localtime lstat64 mkdir
mmap64 munmap nanosleep open64 stat64 sysconf utimes
```

## 2026-07-10 update — LFS *64 aliases added; :memory: acceptance MET

The 17 remaining OS/VFS imports were all present in the crtl EXCEPT five LFS
(`_LARGEFILE64_SOURCE`) aliases that sqlite's os_unix.c uses on 64-bit Linux:
`open64 fcntl64 fstat64 lstat64 stat64 mmap64`. On LP64 these are identical to
the base calls (off_t already 64-bit), so the crtl now forwards them:
- `lib/crtl/src/fcntl.c`: open64, fcntl64
- `lib/crtl/src/sys/stat.c`: fstat64, stat64, lstat64
- `lib/crtl/src/sys/mman.c`: mmap64

With these, `test/csqlite_extended_test.c` (unity-including the crtl srcs)
**links and runs fully libc-free** — `readelf -d` shows ZERO `DT_NEEDED`, opens a
`:memory:` db, runs CREATE/INSERT/SELECT + aggregate queries, closes, exit 0.
**Acceptance (below) is MET for `:memory:`.** crtl file I/O verified working
libc-free end to end (open64→write→fstat64/stat64, regression b234).

### File-backed VFS — two walls found 2026-07-10
1. **SQLITE_CANTOPEN in path resolution — FIXED (crtl, 495a989a).** crtl
   `stat`/`lstat`/`fstat` never set errno; sqlite's `appendOnePathElement` lstat()s
   each path element and branches on `errno==ENOENT`. Stale errno made a missing
   file look like a real error → `unixFullPathname` returned CANTOPEN before open()
   ran. Fixed: wrappers set `errno = -r`. Regression b235.
2. **Segfault in `fillInUnixFile` finder call — FIXED (cfront, e1f28f54).** The
   locking-style finder `(**(finder_type*)pVfs->pAppData)(...)` — a call through a
   deref of a CAST to pointer-to-fnptr — dropped the call. Fixed
   ([[bug-c-call-through-deref-of-fnptr-pointer]], cast form; bare-ident form still
   open). sqlite now opens + CREATES a file-backed db (file appears on disk).
3. **`unixFile` mmap fields at offset 0 — FIXED (cpreproc, fc5b6a59).** The
   `#if SQLITE_MAX_MMAP_SIZE>0` (`0x7fff0000`) evaluated FALSE at the struct (the
   preprocessor didn't parse HEX literals in `#if`), so the mmap fields were dropped
   and `pFile->mmapSize` resolved to offset 0. Fixed by making `#if` parse hex/octal
   ([[bug-c-unixfile-mmap-field-offset-zero]], regression b237). This was the real
   cause of the offset-0 symptom.
4. **Segfault in `unixRead` — FIXED (crtl+PAL, 2026-07-10).** NOT a compiler
   bug: it was a **null-call through an unresolved `aSyscall[]` slot**. cfront's
   linker fills a referenced-but-undefined C symbol with address 0 instead of
   erroring, so every libc syscall sqlite's os_unix.c imported that the crtl did
   NOT define became a `call 0` → SIGSEGV the moment that VFS path ran. On
   `__linux__` (cpreproc predefines it) sqlite takes `USE_PREAD`, so `osPread` =
   `aSyscall[9]` = `pread` — and the crtl had no `pread`, so the FIRST page read
   null-called (the `unixRead` symptom). Behind it, `fillInUnixFile` null-called
   `geteuid`+`fchown` (both active under `HAVE_FCHOWN`, which sqlite defines).
   Full set the crtl was missing: `pread pwrite ftruncate access geteuid fchown
   readlink`. Added libc-free, LP64/ILP32-safe:
   - `lib/crtl/src/stdio.c`: `pread`/`pwrite` — offset-preserving (save `lseek`
     SEEK_CUR, seek, io, restore); no PAL positioned-io syscall exists.
   - `lib/crtl/src/unistd.c`: `ftruncate access fchown geteuid readlink`
     wrappers over new `__pxx_*` PAL bridges.
   - `lib/rtl/pxxcio.pas` + `lib/rtl/platform.pas` +
     `lib/rtl/platform/posix/platform_backend.pas`: `__pxx_ftruncate/access/
     fchown/geteuid/readlink` → raw syscalls (`SYS_ftruncate SYS_faccessat
     SYS_geteuid SYS_fchown SYS_readlinkat`, numbered for x86_64/i386/aarch64/
     arm32/rv32; `access`→`faccessat(AT_FDCWD)`, `readlink`→`readlinkat`).
     ESP backend gets `PAL_ERR_UNSUPPORTED` stubs.
   Regression `test/crtl_posix_io_leaf_b238.c` (Makefile, exit 42, 0 NEEDED).
   Integration probe `test/csqlite_file_probe.c`: file-backed CREATE/INSERT then
   **close+reopen+SELECT reads the row back off disk** (`row: 1 hello`), producing
   a valid SQLite file, fully libc-free (0 DT_NEEDED), verified native +
   aarch64/i386/arm32 under qemu (rv32 shares the aarch64 asm-generic table), with
   AND without the mmap path. **File-backed VFS is now working end to end.**

## Acceptance

- A libc-free sqlite driver (unity-including the crtl srcs) opens, executes SQL,
  and closes a `:memory:` database without faulting and with no `DT_NEEDED` (or
  only the intended ones). **MET 2026-07-10** (csqlite_extended_test, 0 NEEDED).
- File-backed VFS: create + reopen + read-back off disk, libc-free, native +
  cross. **MET 2026-07-10** (walls 1-4 all cleared; csqlite_file_probe).
