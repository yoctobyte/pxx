---
slug: bug-c-sqlite-with-threadsafe-stops-at-a-stray-BEGIN_DECLS
track: C
type: bug
prio: 30
status: open
found: 2026-09-05
found-by: frankC
owner: ""
blocked-by: []
summary: "TWO WALLS, and --threadsafe caused neither of them in the way the title suggests. (1) FIXED 2026-09-24 (frankS): `--threadsafe --emit-obj` and `--threadsafe --shared` refused EVERY C file, `int f(int x){return x+1;}` included, with `call to a runtime stub that was never emitted`. MECHANISM: every stub-address variable reads 0 as never emitted. An executable's entry stub owns code offset 0, but a C object or shared library has no entry stub, so the first runtime stub landed at 0. Under --threadsafe that is the heap-lock slow stub, and the heap lock's own call to it tripped the guard. The C driver now plants a one-instruction trap at offset 0 in object/shared mode off ESP. With that, `--threadsafe -DSQLITE_OMIT_LOAD_EXTENSION --emit-obj sqlite3.c` builds (4617 procs). (2) OPEN, and it has nothing to do with --threadsafe: `__BEGIN_DECLS` comes from the HOST /usr/include/dlfcn.h, because crtl has no <dlfcn.h> and sqlite includes it unless SQLITE_OMIT_LOAD_EXTENSION is set. It reproduces with -DSQLITE_THREADSAFE=0. What would close it: a crtl <dlfcn.h> routed to the PAL loader that lib/rtl/dynlibs.pas already uses (PalDlOpen/PalDlSym/PalDlClose: honest stubs by default, real dlopen under -dPXX_DYNLIB_LIBC). No crtl C source calls the PAL today, so the bridge is the design part.""
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
