---
track: B
prio: 45
type: bug
owner: claude-B-night
status: done
---

# A spurious `DT_NEEDED libc.so.6` is emitted for a binary that imports nothing

- **Type:** bug (C frontend / ELF emission) — **Track C**, re-laned from B on
  2026-08-02 once diagnosed: the defect is not in `lib/crtl` at all.
- **Found:** 2026-08-02 while adding the byte-order declarations to
  `<netinet/in.h>` ([[feature-crtl-libc-gap-batch-2026-08]]). **Pre-existing** —
  not introduced by that change.

## Measured

```c
#include <arpa/inet.h>            /* the OLD path, unchanged by anything today */
int main(void){ return (int)htons(1); }
```

| program | linkage |
| --- | --- |
| `htons` (or any other socket.c symbol) | **dynamically linked, NEEDED libc.so.6** |
| the same file without it | statically linked |
| a C program using only string/stdio/errno | statically linked |

True on every target (x86-64, i386, aarch64, arm32) and through both
`<arpa/inet.h>` and the newly-added `<netinet/in.h>` declarations, so it is a
property of pulling `socket.c` in, not of either header.

## Why it matters

The syscall-only core being libc-free is a design invariant — it is why
`-dPXX_DYNLIB_LIBC` exists as an *opt-in* for the loader, and why the ESP and
static-target stories work at all. A program acquires a glibc runtime dependency
here by calling a **pure byte-swap function**, which is about as far from
needing libc as a function gets.

The practical bite is portability, and it is not hypothetical: such a binary
cannot run under `qemu-aarch64`/`qemu-arm` on a box without a target sysroot,
which is exactly how it was noticed — a test calling `htons` could not be
cross-verified while the identical test without it could.

## Diagnosed 2026-08-02 — the binary imports NOTHING

The decisive measurement: the produced binary has

```
Dynamic section:
  (NEEDED)  Shared library: [libc.so.6]
```

and **zero dynamic symbols** (`readelf --dyn-syms` lists no FUNC or OBJECT).
It also runs standalone here. So this is not a real dependency being discovered
— it is a `DT_NEEDED` emitted for a library nothing is imported from.

Narrowed:

| program | linkage |
| --- | --- |
| references `htons` (in `socket.c`) | dynamic |
| references `socket()` (also `socket.c`) | dynamic |
| references `strlen` (in `string.c`) | **static** |
| includes any of socket.c's headers, references nothing | static |
| declares AND calls a bare `extern int __pxx_foo(int)` | static |

So it is triggered by pulling the `socket.c` translation unit in — any symbol
of it will do — and not by a header, and not by an `extern` declaration alone.

`socket.c` declares only `__pxx_*` externs, which are Pascal-side PAL helpers
resolved internally, never libc symbols. The relevant compiler code is
`compiler/cparser.inc:8059` / `:8128`, which defaults an external's soname to
`libc.so.6` and then decides `forceSystemExternal`; something on that path
registers the soname for symbols that are subsequently satisfied internally, and
the ELF writer emits the `NEEDED` without checking that anything was actually
imported.

**Why it is Track C, not B.** Nothing in `lib/crtl` is wrong: the externs are
correctly declared and correctly resolved. The fix is either to stop registering
the soname for an external that resolves internally, or to prune a `DT_NEEDED`
with no importing symbols at emission — both in `compiler/**`, which Track B
does not edit. It may well hand off again to Track A if the right fix is in the
ELF writer rather than the C frontend.

Do not "fix" it by duplicating the byte-swaps somewhere else — that hides the
dependency for four functions and leaves it for every other socket symbol, and
the actual defect (a NEEDED with no imports) would survive untouched.

## Gate

A C program calling `htons` (or any other `socket.c` symbol, or nothing at all)
is statically linked and has no `DT_NEEDED` it does not import from. Then the
byte-order assertions can be restored to `test/cerrno_strings.c` — they were
removed precisely because this made that test unrunnable under qemu on targets
with no sysroot, and their return would be the end-to-end proof.

## ROOT CAUSE CORRECTED (2026-08-03) — the binary DOES import, and it is not a Track C bug

**The "imports NOTHING" diagnosis above is wrong, and it is wrong for a tooling
reason worth recording.** `readelf --dyn-syms` needs section headers; pxx emits
these binaries with program headers only ("no section header" in `file` output),
so readelf lists nothing whatever the dynamic segment says. Reading the same
binary through the segment tells the truth:

```
$ objdump -T htonbin
DYNAMIC SYMBOL TABLE:
0000000000000000      DF *UND*  0000000000000000 htons
```

One dynamic symbol, one RELA entry (`DT_RELASZ` = 24 = exactly one), and the
`DT_NEEDED` is honest: `htons` really is being imported from glibc. The ELF
writer is fine — it emits one NEEDED per distinct library over `ExternalProc[]`,
and `RegisterExternal` only fires for a proc still marked external at codegen.

So there is nothing to prune and nothing to fix in `compiler/**`. **Use
`objdump -T` (or `readelf -d` + `DT_RELASZ`), never `readelf --dyn-syms`, on a
pxx binary.**

### The actual defect (Track B, `lib/crtl`)

crtl's sibling auto-pull is by convention: `crtl/include/<name>.h` pulls
`crtl/src/<name>.c` (`CPCrtlSrcOf`, `compiler/cpreproc.inc`). The byte-order and
socket functions are DECLARED in `arpa/inet.h`, `netinet/in.h` and
`sys/socket.h`, but IMPLEMENTED in `crtl/src/socket.c` — a path no one of those
headers maps to (`src/arpa/inet.c`, `src/netinet/in.c`, `src/sys/socket.c` all
do not exist). The impl is therefore never pulled, the prototype stays external,
and the call falls back to a glibc dynamic import. It *works* on glibc, which is
why it read as a phantom NEEDED rather than an unresolved symbol.

`strlen` is static precisely because `string.h` ↔ `src/string.c` obeys the
convention.

### Proven fix (measured here, then reverted — `lib/**` is Track B's)

1. move `lib/crtl/src/socket.c` → `lib/crtl/src/sys/socket.c` (so `sys/socket.h`
   pulls it by the existing convention — `src/sys/` already holds `mman.c`,
   `stat.c`, `time.c`);
2. `#include <sys/socket.h>` from `arpa/inet.h` and `netinet/in.h`, so a program
   that includes only those still reaches the impl.

Measured with exactly that change in place:

| | before | after |
| --- | --- | --- |
| `#include <arpa/inet.h>` + `htons(1)` | dynamically linked, NEEDED libc.so.6, imports `htons` | **statically linked, no imports** |
| `htons(1)` / `htonl(1)` values | 256 / 16777216 | 256 / 16777216 (unchanged, = gcc) |

Re-laned to **Track B**. The gate stands as written, including restoring the
byte-order assertions to `test/cerrno_strings.c` — with this fix that test is
statically linked again and runs under qemu with no sysroot.


## FIXED 2026-08-05 (Track B) — commit `8d7c47f8f`, verified on origin/master

The diagnosis above was right and the prescription needed one adjustment, which
the first build found immediately.

**`src/sys/socket.c` does not work** — that was the prescribed destination, and
it fails to compile: the auto-pull fires the moment `<sys/socket.h>` COMPLETES,
which is *before* `<netinet/in.h>` (whose first act is to include
`<sys/socket.h>`) has defined `in_addr_t` and `struct sockaddr_in`, and too late
to pull them since that header's guard is already set. Result:
`stray token at top level: 'in_addr_t'`.

**The impl therefore lives at `src/netinet/in.c`**, where `<netinet/in.h>` pulls
it with every type it needs in scope. That alone fixes `<arpa/inet.h>` and
`<netinet/in.h>` (which is how essentially all real socket code reaches these
functions, since `sockaddr_in` comes from there).

**`src/sys/socket.c` is now a small shim** so `#include <sys/socket.h>` *alone*
still reaches the impl. It has to test the guard rather than include
unconditionally:

```c
#ifndef PXX_CRTL_NETINET_IN_H
#include <netinet/in.h>
#endif
```

because **a guard-suppressed no-op include still triggers the sibling-impl
pull** — an unconditional include here would pull `src/netinet/in.c` while
`<netinet/in.h>`'s own body was unfinished, reproducing the exact failure it
works around. The `#ifndef` distinguishes "we were included by netinet/in.h,
which will pull the impl itself" from "we are first, so run it for real".

### Measured

| program | before | after |
| --- | --- | --- |
| `<arpa/inet.h>` + `htons`/`htonl` | dynamic, NEEDED libc.so.6, 2 imports | **static, 0 NEEDED, 0 imports** |
| `<sys/socket.h>` + `socket()` | dynamic, NEEDED libc.so.6, 1 import | **static, 0 NEEDED, 0 imports** |
| `htons(1)` / `htonl(1)` values | 256 / 16777216 | unchanged, = gcc |

Include-order check: `<sys/socket.h>`, `<netinet/in.h>`, `<arpa/inet.h>` and
`<netdb.h>` each compile standalone.

### Gate — met, including the part the ticket asked for

- `test/cerrno_strings.c` has its byte-order assertions back (htons/ntohs/htonl/
  ntohl values plus round-trips), and is **byte-identical to a gcc build on
  stdout and stderr separately**.
- It is **statically linked on x86-64, i386, arm32, aarch64 AND riscv32**, with
  identical output on all five — the cross runs that this bug used to make
  impossible.
- `make lib-test` now asserts the **linkage**, not just the output: the output
  diff passes either way on a glibc host, so without that assertion the fix
  would regress silently and only a sysroot-less cross target would notice.
- C conformance re-run for the regression risk crtl changes carry:
  **i386 219 pass / 0 fail**, **riscv32 219 pass / 0 fail** (1 skip, the known
  VLA case).
- `tools/gate.sh lib` GREEN.

### Swept while here

All 317 buildable `test/c*.c` programs were checked for a `DT_NEEDED`. Three
have one, and none is this bug: `crtl_libc_oracle` links libc **by design**
(it is the oracle), `cwide_string_literal` imports `wcslen` (crtl has
`include/wchar.h` but no `src/wchar.c` — the same declared-but-not-implemented
shape, filed separately), and `cquickjs_prereq` needs `--threadsafe`
(filed separately: without that flag the binary builds clean and then dies at
load with `undefined symbol: __pxx_pmutex_init`).

## Log
- 2026-08-05 — resolved, commit PENDING.
