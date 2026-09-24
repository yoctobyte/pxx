---
slug: bug-c-sqlite-with-threadsafe-stops-at-a-stray-BEGIN_DECLS
track: C
type: bug
prio: 30
status: done
found: 2026-09-05
found-by: frankC
owner: ""
blocked-by: []
summary: "FIXED 2026-09-24 (frankS). TWO WALLS, and --threadsafe caused neither of them the way the title suggests. (1) a4dea4c09b: in a C object or shared library the first runtime stub landed at code offset 0, which every stub-address variable reads as never emitted, so `--threadsafe --emit-obj/--shared` refused EVERY C file. Offset 0 is now reserved with a trap instruction. (2) this commit: `__BEGIN_DECLS` came from the HOST /usr/include/dlfcn.h, because crtl had no <dlfcn.h>; sqlite includes it unless SQLITE_OMIT_LOAD_EXTENSION is set. crtl now has <dlfcn.h> + src/dlfcn.c over the PAL loader Pascal's dynlibs uses, via new __pxx_dl* bridges in pxxcio.pas. Default libc-free build: dlopen returns NULL and dlerror says why. -dPXX_DYNLIB_LIBC: the real loader, output equal to gcc -ldl. Now `--threadsafe --emit-obj sqlite3.c` builds with no -D at all (4654 procs), and so does `-DSQLITE_THREADSAFE=0`. Without either, sqlite's default THREADSAFE=1 meets the designed refusal `__pxx_pmutex_init needs the thread-safe runtime: rebuild with --threadsafe`, which is correct and names its fix.""
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

## 2026-09-24 (frankS): the --threadsafe half was an object-mode offset-0 collision, fixed

Reduced from the amalgamation to one line: `int f(int x){return x+1;}` with
`--threadsafe --emit-obj` refused. A backtrace in a -g compiler shows
IREmitCodeCall(addr=0) <- EmitHeapLockStubs <- EmitHeapLockSlowStub <-
ParseCProgram. HeapLockSlowAddr WAS emitted, at CodeLen 0, which is the
sentinel. Plain --emit-obj also puts a stub at 0 (the div-zero stub; the
object's first bytes are its write + exit_group(200)). It got away with it only
because C division calls PXXDivZero by name.

Guard: test/c_threadsafe_object_offset_zero.c, built `--threadsafe --emit-obj`
and `--threadsafe --shared`, each linked by gcc and run (answers 42). The rows
are at the head of test-emit-obj. Pin v421 refuses the file. Also verified:
make test-emit-obj and make test-c-abi-mixed-link, x86_64 and i386, both green.

## 2026-09-24 (frankS): the dlfcn half, closed

lib/crtl/include/dlfcn.h, lib/crtl/src/dlfcn.c, and pxxcio's __pxx_dlopen /
__pxx_dlsym / __pxx_dlclose / __pxx_dl_available over PalDlOpen/PalDlSym/
PalDlClose/PalHasDynlib. RTLD_* take glibc's values and are not honoured (the
PAL takes a name only), and dlopen(NULL) is refused through dlerror. The
regenerated compiler/crtl_names.inc means a hand-declared `void
*dlopen(const char *, int);` now pulls the crtl body instead of becoming a
silent libc import. Measured: it answers NULL in the default build.

Rows (test-core, beside the tag rows): test/c_crtl_dlfcn.c, default build
(test/c_crtl_dlfcn.expected) and -dPXX_DYNLIB_LIBC (c_crtl_dlfcn_libc.expected
= gcc -ldl output). Control: with dlfcn.h moved aside, the fixture reproduces
this ticket's exact refusal, `stray token at top level: '__BEGIN_DECLS'`. The
pinned compiler is NOT a control here, because it reads crtl from the live
tree. Also:
- the fixture builds and runs on i386, arm32, aarch64 and riscv32, and builds
  for riscv32 ESP;
- test/crtl_declaration_census.sh: 606 declared, all defined, no libc imports;
- make test-sqlite-parity PASS;
- gate quick GREEN (after regenerating crtl_names.inc, which the gate
  correctly flagged as stale).

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
