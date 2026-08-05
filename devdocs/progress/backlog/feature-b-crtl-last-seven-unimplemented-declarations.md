---
summary: "The crtl declarations still without bodies — now 3: atexit, poll, ioctl (chmod, umask, msync and mremap landed 2026-08-05). Each is declared, so a caller binds silently to libc.so.6 and the 'self-contained' binary grows a DT_NEEDED"
type: feature
track: B
prio: 40
---

# crtl: the last declared-but-unimplemented functions

- **Type:** feature (gap) — Track B (`lib/crtl`, `lib/rtl/pxxcio.pas` bridges)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/crtl_decl_probe.sh`. Was 366 declared / 359 implemented;
  **`chmod`, `umask`, `msync` and `mremap` landed 2026-08-05**, so it is now
  363 / **3** remaining.

## Why a missing body is worse than a missing declaration

Each of these is **declared** in a crtl header, so the C frontend's
unresolved-extern fallback binds the call to `libc.so.6`. On a glibc host the
program then produces **correct output** — and quietly stops being
self-contained. `clock_gettime` was exactly this and was fixed 2026-08-05:

```
$ readelf -d prog | grep NEEDED
 0x0000000000000001 (NEEDED)  Shared library: [libc.so.6]
```

The values were right, the linkage was not. **Assert the linkage, not just the
output** — that is what this probe is for.

## The seven, with what each needs

| function | header | note |
| --- | --- | --- |
| **`atexit`** | `stdlib.h` | The awkward one — see below. Today it is a hard *runtime* link error (`undefined symbol: atexit`), so at least it is loud. |
| **`poll`** | `poll.h` | `PalPoll` exists but is **per-handle** (`PalPoll(handle, events, timeoutMs)`); real `poll(fds[], nfds, timeout)` needs an array-shaped PAL bridge, not a loop over the existing one (a loop cannot block on the set). |
| **`ioctl`** | `sys/ioctl.h` | No general bridge. `__pxx_isatty` already does the one TCGETS case crtl needs; a generic `ioctl(fd, req, arg)` is a new PAL entry. Note ESP refuses it. |
| ~~`chmod`~~ | `sys/stat.h` | **DONE 2026-08-05.** Goes through `fchmodat(AT_FDCWD, …)` — aarch64 and riscv have no legacy `chmod` syscall, same as `symlink`/`link`. |
| ~~`umask`~~ | `sys/stat.h` | **DONE 2026-08-05.** The one syscall here with no error path: it always succeeds and returns the previous mask, so no -1/errno conversion. |
| ~~`msync`~~ | `sys/mman.h` | **DONE 2026-08-05.** No-op success, matching munmap/mprotect in the same file — `mmap` there is a stub returning MAP_FAILED, so there is never a mapping to flush. |
| ~~`mremap`~~ | `sys/mman.h` | **DONE 2026-08-05.** Must return a POINTER, so it cannot pretend: fails like `mmap` does (MAP_FAILED + ENOMEM). Linux-specific and variadic; the optional 5th arg is not read. |

`chmod` and `umask` were the cheapest and are done. Their syscall numbers were
added to all five arch tables in `platform_backend.pas` and **verified by running
the probe on x86-64, i386, arm32 and aarch64** — a wrong number there is exactly
how `exit_group` came to be `fgetxattr` on 32-bit
([[bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit]]'s sibling,
fixed the same night). riscv32 shares aarch64's asm-generic numbers and is not
runnable here.

## `atexit` cannot be finished inside crtl

crtl owns `exit()`, so registering handlers and running them there is easy. It
does **not** own the other exit path: the C entry stub is `call main;
exit_group(retval)`, emitted by the compiler, and a plain `return` from `main`
bypasses crtl entirely. So a crtl-only `atexit` would run handlers for `exit()`
and silently skip them for `return` — which is worse than not having it, because
it would look implemented.

There is already a mechanism to hook: `__pxx_run_finalizers` /
`EmitFinalizerRunnerBody` (`symtab.inc:5616`, `cparser.inc:8453`), the shell
every Pascal exit path calls. The C entry stub does not call it. Wiring it in —
so both `return` from `main` and `exit()` run registered handlers, in LIFO order
— is a **Track C/A** change; the crtl half (the handler table) is Track B and
should land with it, not before.

Suggested split: file the stub change as a Track C ticket, then implement
`atexit` here against it.

## Gate

`tools/crtl_decl_probe.sh` reports 0 unimplemented; each new function
byte-matches gcc in `tools/gcc_diff_probe.sh`; **and** a program calling it has
no `DT_NEEDED` (`readelf -d`).
