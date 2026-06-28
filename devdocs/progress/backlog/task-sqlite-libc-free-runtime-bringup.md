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

## Acceptance

- A libc-free sqlite driver (unity-including the crtl srcs) opens, executes SQL,
  and closes a `:memory:` database without faulting and with no `DT_NEEDED` (or
  only the intended ones).
