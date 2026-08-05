---
summary: "The 7 crtl declarations still without bodies — atexit, poll, ioctl, chmod, umask, msync, mremap. Each is declared, so a caller binds silently to libc.so.6 and the 'self-contained' binary grows a DT_NEEDED"
type: feature
track: B
prio: 40
---

# crtl: the last 7 declared-but-unimplemented functions

- **Type:** feature (gap) — Track B (`lib/crtl`, `lib/rtl/pxxcio.pas` bridges)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/crtl_decl_probe.sh` (366 declared, 359 implemented).

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
| **`chmod`** | `sys/stat.h` | Simple syscall; `fchmod` is already bridged (`__pxx_fchmod`), so this is the path-taking sibling. |
| **`umask`** | `sys/stat.h` | Simple syscall, process-global state. |
| **`msync`** | `sys/mman.h` | mmap family; only worth it alongside a real mmap story. |
| **`mremap`** | `sys/mman.h` | Same. Linux-specific. |

`chmod` and `umask` are the cheapest and are ordinary things build tooling does.

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
