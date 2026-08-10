---
blocked-by: feature-c-entry-stub-must-run-finalizers
summary: "The last crtl declaration without a body — now just atexit (poll landed 2026-08-09) (chmod, umask, msync, mremap and ioctl landed 2026-08-05). Each is declared, so a caller binds silently to libc.so.6 and the 'self-contained' binary grows a DT_NEEDED"
type: feature
track: B
prio: 40
owner: claude-B
---

# crtl: the last declared-but-unimplemented functions

- **Type:** feature (gap) — Track B (`lib/crtl`, `lib/rtl/pxxcio.pas` bridges)
- **Status:** working
- **Opened:** 2026-08-05
- **Found by:** `tools/crtl_decl_probe.sh`. Was 366 declared / 359 implemented;
  **`chmod`, `umask`, `msync`, `mremap` and `ioctl` landed 2026-08-05**, so it is
  now 367 declared / 365 implemented / **2** remaining.

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
| ~~`ioctl`~~ | `sys/ioctl.h` | **DONE 2026-08-05.** This row was WRONG: `PalIoctl` was already a fully general `syscall(SYS_ioctl, fd, cmd, argp)` — `__pxx_isatty` had been using it for the single TCGETS case all along. No new PAL entry was needed, only `__pxx_ioctl` exposing it and a crtl wrapper doing the -1/errno conversion. Measure before believing a scoping line. ESP: IDF routes to `lwip_ioctl`, bare answers PAL_ERR_UNSUPPORTED, which surfaces as -1/errno — a refusal, not a wrong answer. |
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

## 2026-08-09 — `poll` done; `atexit` is all that is left

**`poll`** shipped. It did need the new PAL entry the ticket predicted, and for
the reason it gave: `PalPoll` is per-handle, and a set poll cannot be a loop
over it, because the whole point is to block on the WHOLE set — a loop either
blocks on the first descriptor or busy-spins the rest.

- `PalPollSet(fds, nfds, timeoutMs)` in `platform.pas`, over `ppoll` in the
  posix backend and `lwip_poll` under ESP-IDF (bare answers
  `PAL_ERR_UNSUPPORTED`, the deliberate Track S refusal).
- Nothing is repacked: C's `struct pollfd` is int-then-two-shorts, which is
  exactly the 8-byte record `PalBackendPoll` already hands the kernel, so the
  caller's own array is what `ppoll` writes revents into.
- `__pxx_poll` bridge, `lib/crtl/src/poll.c` doing the -1/errno conversion.

Measured against the gcc oracle on the same file, identical on **x86-64, i386,
arm32 and aarch64** — including the cases a per-handle loop cannot pass (write
to the SECOND of two pipes and require exactly it; then both). `readelf -d`
shows **0 DT_NEEDED**, which is the assertion this ticket exists for.

`tools/crtl_decl_probe.sh`: **367 declared, 1 unimplemented** (was 2).

**`atexit` is unchanged and still cannot be finished here** for the reason
written above: crtl owns `exit()` but not the C entry stub's `return`-from-main
path, so a crtl-only atexit would look implemented and silently skip handlers.
That half is now filed as [[feature-c-entry-stub-must-run-finalizers]], as this
ticket's own "suggested split" line proposed, and this ticket is blocked on it.
The crtl handler table is a small job once the stub calls the finalizer shell.

Also surfaced by the probe, filed rather than fixed: **20 build-failures, all
`pthread.h`**, every one of them `needs the thread-safe runtime: rebuild with
--threadsafe`. That is not an unimplemented body — it is the reach-based gate,
recorded as corroboration on
[[decide-threadsafe-gate-is-reach-based-not-use-based]].

Regression test: `test/crtl_poll_set.c`, in `make lib-test`, asserting the
values AND the absence of DT_NEEDED.

## 2026-08-10 (Track B): blocker CONFIRMED by measurement, and the symptom is worse than filed

Re-checked whether this was still really blocked — the pattern this session has
been that Track B's blocked tickets often were not. **This one is**, and the
mechanism is now pinned down.

**The symptom is worse than the summary says.** The summary describes `atexit`
binding silently to libc and growing a `DT_NEEDED`. Measured, it does that AND
the program then **fails to start**:

```
ae_pxx: symbol lookup error: ... undefined symbol: atexit
exit=127          (gcc prints: main done / bye2 / bye1)
```

So any C program calling `atexit` is dead on arrival, not merely non-self-contained.

**Why Track B cannot finish it.** The C entry stub is `call main(), then
exit_group(main's return)` — a direct syscall (`compiler/cparser.inc:8371`). It
never routes through crtl's `exit()`, so a handler list living in crtl could not
be run on a normal return from `main`.

The obvious Track-B-only escape does not exist either: `lib/rtl/pxxcio.pas` IS
Track B's file, so a `finalization` section there would have been a legitimate
hook. **Tested directly — it does not run.** A finalization writing a marker
produced no output for a C program that returns from `main`:

```
main done          <- and no FINALIZER-RAN
```

(`__pxx_run_finalizers` does exist and `EmitFinalizerRunnerBody` wires it, but at
**Halt sites** only, which a normal return is not.) That is precisely what
[[feature-c-entry-stub-must-run-finalizers]] is about, so the recorded blocker is
right.

**Deliberately NOT shipping a partial `atexit`.** Giving crtl a body that runs
handlers from `exit()` but silently skips them on a return from `main` would
turn a LOUD failure (won't start) into a SILENT wrong one (cleanup never runs,
program looks fine) — real C code registers a flush/cleanup handler and then
returns from main. Per `devdocs/dev/platonic-no-workarounds`, the crash stays
until the entry stub can run them.

**For whoever takes the Track C ticket:** the whole of this one is `atexit` now,
and the fix there makes it a few lines here — a handler array, LIFO order,
`exit()` and the stub both draining it. `test/ae.c`-style repro is three lines
and gcc's output is the expectation.
