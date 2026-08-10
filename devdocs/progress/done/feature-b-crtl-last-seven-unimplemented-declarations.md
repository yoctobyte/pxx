---
summary: "The last crtl declaration without a body — now just atexit (poll landed 2026-08-09) (chmod, umask, msync, mremap and ioctl landed 2026-08-05). Each is declared, so a caller binds silently to libc.so.6 and the 'self-contained' binary grows a DT_NEEDED"
type: feature
track: B
prio: 40
owner: claude-B
---

# crtl: the last declared-but-unimplemented functions

- **Type:** feature (gap) — Track B (`lib/crtl`, `lib/rtl/pxxcio.pas` bridges)
- **Status:** done
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

## 2026-08-10 (Track B) — blocker FIXED upstream; this now waits on a PIN, not on code

Track C landed the entry-stub half ([[feature-c-entry-stub-must-run-finalizers]]):
`EmitCallProc` resolves `__pxx_run_finalizers` as a forward, so it is
target-independent, and the only per-target work was preserving `main`'s return
value across the call — wired for all five targets. Proven by giving `pxxcio` a
temporary finalization section and running a C program that only `return 3`s:
`main-returns / FINALIZER-RAN / exit=3`. The probe file was reverted; all 385 C
tests are identical vs pinned.

**So the crtl half is a few lines — but Track B cannot gate it yet.** Track B
builds with `$(PXX_STABLE)` = `stable_linux_amd64/default/pinned`, and the entry
stub is emitted by *whichever compiler builds the program*. The fix is not in the
pinned binary, so an `atexit` written today would be tested against a stub that
still does not drain handlers, and would appear to fail for a reason that is not
its own.

This is exactly the partial-`atexit` hazard recorded above, arriving from the
other side: previously the missing piece was the stub, now it is the pin. **Do
not ship against an unpinned enabler** — the failure mode is a handler table
that looks implemented and silently never runs, which is worse than today's loud
`undefined symbol: atexit`.

Order of operations for whoever takes this:

1. Track A pushes the entry-stub fix and runs `make pin` (`stabilize-fast`, then
   commit `stable_linux_amd64/**`).
2. Confirm the pin actually carries it — the three-line `return`-from-main repro
   with a registered handler, built with `$(PXX_STABLE)`, not with a local HEAD
   build. Track B never rebuilds the compiler, so the pin IS the ground truth.
3. Then the crtl work: handler array, LIFO drain, both `exit()` and the stub
   path. gcc is the expectation; assert **no `DT_NEEDED`** (`readelf -d`), which
   is the property this whole ticket exists for.

Note the ticket's own scope line stays honest: the **environ** half
([[bug-...-environ]] direction) is NOT solved by this — it needs an *init*
phase, and what landed is the *fini* phase.
### Added by Track A, 2026-08-10 — one fact Track B's note does not have

**The hook is INERT today.** No auto-pulled unit has a `finalization` section
(checked `pxxcio`, `builtinheap`), so `__pxx_run_finalizers` walks an empty list
and all 385 C tests are differentially identical to `pinned`. That is why the
landed change is observably a no-op and why the pin carrying it will look like
nothing changed.

Consequence for step 3: once the handler table exists, **if handlers do not
fire, suspect crtl's registration, not the stub** — the stub's call is verified
present (byte pattern, resolved rel32) and verified to execute (the reverted
`pxxcio` probe). That is the one debugging step this ordering makes confusing,
so it is written down.

Track B's reading of the pin dependency is correct and supersedes Track A's
original "UNBLOCKED" framing, which understated it: the code blocker is gone,
the pin is not.

## 2026-08-10 (Track A) — steps 1 and 2 are DONE: pinned v256, and the pin is verified

Track B's order of operations, executed:

**1. Pinned.** `make stabilize-fast && make pin` → **v256**
(`44db8460bb761c135b2cc38752c5690160ca56a7e15591e74436ab1e96f441db`),
`stable_linux_amd64/**` committed.

**2. Confirmed the pin actually carries it** — and deliberately the way Track B
asked, with `$(PXX_STABLE)` rather than a local HEAD build, because Track B
never rebuilds the compiler and so the pin IS the ground truth:

```
$ stable_linux_amd64/default/pinned pinfin.c pinfin     # a C program that only `return 3`s
main-returns
PIN-FINALIZER-RAN
exit=3
```

(with `pxxcio` given a temporary `finalization` section for the probe; reverted,
`git status` clean).

So the finalizer drains on the `return`-from-main path **under the pinned
compiler**, and main's exit code survives the call. The hazard Track B named —
shipping a handler table against an unpinned enabler, giving an `atexit` that
looks implemented and silently never runs — no longer applies.

**Step 3 is yours**, unchanged: handler array, LIFO drain, both `exit()` and the
stub path, gcc as the expectation, and assert no `DT_NEEDED` (`readelf -d`).
Note the inert-hook caveat above still holds until crtl registers its drain.

## 2026-08-10 (Track B) — step 3 DONE: `atexit` ships, gcc-identical on all five targets

The pin carried it, so the crtl half went in as predicted. The last
declared-but-unimplemented crtl function now has a body.

**Where the table lives, and why it is not in crtl.** In `lib/rtl/pxxcio.pas`
(Pascal), not `lib/crtl/src/stdlib.c`. The hook the entry stub walks is
`__pxx_run_finalizers` → **unit finalization sections**, which is Pascal-only,
and the crtl↔Pascal bridge is one-directional: C resolves bodied Pascal procs
internally (FindProc), never the reverse. A list on the C side could therefore be
drained by `exit()` and would be **silently skipped on the return-from-main
path** — the exact partial-`atexit` hazard this ticket has been refusing to ship
since 2026-08-05, just arriving from a third direction. One list in Pascal serves
both paths.

- `__pxx_atexit(fn)` / `__pxx_atexit_run` in `pxxcio.pas`; crtl's
  `atexit()` is a two-line bridge and `exit()` drains before `__pxx_exit`.
- `_Exit` and `abort` deliberately do **not** drain (C99 7.20.4.4 / 7.20.4.1).
- Drain is LIFO and **pops**, which is what makes `exit()` from inside a handler
  behave: it re-enters, finds the remaining prefix, and never repeats one. gcc
  agrees exactly, including the exit code (9, from the handler's own `exit`).
- **Not a fixed cap.** A 64-slot array passed the standard's ≥32 requirement and
  still diverged from the oracle at 100 registrations (gcc `ok=100`, ours
  `ok=64 fail=36`), so the list grows on the shared PXXAlloc heap from 32,
  doubling. OOM is now the only failure.

**Measured vs the gcc oracle**, four programs (return-from-main, `exit()`,
`_Exit()`, 100 registrations) — **identical output and identical exit codes**,
`readelf -d` = **0 DT_NEEDED**, which is the property this ticket exists for.
Cross: **arm32, aarch64 and riscv32 identical too**. Regression test
`test/crtl_atexit.c` in `make lib-test`, asserting values, exit codes AND the
absence of DT_NEEDED. `compiler/crtl_names.inc` regenerated (one entry:
`atexit:stdlib.h`) — `gen_crtl_map.py --check` is what caught that, as designed.

### Two compiler bugs fell out, both filed, neither worked around in spirit

1. [[bug-a-assignment-through-a-pointer-returned-by-a-function-call-is-dropped]]
   — `Slot(i)^ := v` compiles clean and **stores nothing**; reading `Slot(i)^` is
   fine and `t := Slot(i); t^ := v` is fine, so only the lvalue arm is broken.
   This is what made the first heap-backed version segfault, and the first
   suspicion was `PXXRealloc` (cleared by probing it directly — measure, do not
   reason). pxxcio inlines the slot cast at both use sites with a comment naming
   the ticket; restore the `AtExitSlot` helper when it closes.
2. [[bug-c-i386-entry-stub-hands-main-argc-and-argv-swapped]] — found only
   because the new test selects its sub-mode from `argv[1]`: on **i386** every C
   `main` gets garbage argc (a stack address) and a bogus argv, because the stub
   pushes cdecl order while a CProgramMode callee reads leftmost-first. Verified
   **not** a v256 regression (same under the previous pin) and Pascal-side
   `ParamCount` on i386 is unaffected. That is why the i386 rows of this test
   pass by falling into the default branch rather than by testing anything.

### One correction to this ticket's own bookkeeping

`tools/crtl_decl_probe.sh` now reads **372 declared / 9 unimplemented**, not
"1". `atexit` is gone from the list; all 9 are `math.h` (`sin`, `cos`, `tan`,
`exp`, `log2`, `log10`, `sinh`, `cosh`, `tanh`) and are **probe
false-positives** — they have bodies under `__crtl_`-prefixed names reached
through function-like macros, a deliberate scar from the b377 Pascal-twin
collision (`lib/crtl/src/math.c:29`). The probe counts declarations, and a macro
is not one. Not filed as a gap; noted so the next reader does not re-chase it.
The 21 pthread BUILDFAILs are the reach-based `--threadsafe` gate, unchanged.

## Log
- 2026-08-10 — resolved, commit c4a1d76f6.
