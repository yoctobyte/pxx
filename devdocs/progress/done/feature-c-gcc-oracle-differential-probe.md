---
summary: "tools/gcc_diff_probe.sh — the gcc-oracle differential over crtl's EXISTING functions (the C mirror of fpc_diff_probe.sh), with a --target cross mode; found 6 bugs on its first two runs"
type: feature
track: B
prio: 50
---

# `tools/gcc_diff_probe.sh` — gcc-oracle differential for crtl

- **Type:** feature — Track B (`lib/crtl` verification tooling)
- **Status:** done
- **Opened / closed:** 2026-08-05
- **Why:** the 2026-08-04/05 handoff named this the missing fourth angle —
  "nothing does for C behaviour what `fpc_diff_probe` does for Pascal: a
  gcc-oracle differential over crtl's *existing* functions, not its missing
  ones." `tools/crtl_decl_probe.sh` answers *is it implemented*;
  `test/crtl_libc_oracle.c` is one recorded batch. Neither is a harness you can
  add a case to in ten seconds.

## What it is

56 cases over string.h, stdlib.h, ctype.h, stdio.h, time.h, unistd.h and
integer edges. Each case is a whole C program run under gcc and under pxx
(libc-free — a glibc-linked run would agree trivially); stdout+stderr and the
exit code are compared.

Deliberately carried over from `fpc_diff_probe.sh`, because each was a lesson:

- **a no-oracle skip is not a pass** — a gcc compile failure prints `SKIP` and is
  counted. It caught a missing `#include <stddef.h>` in one of my own cases
  within a minute of the first run.
- **`vis()`** renders control bytes on both sides, so a whitespace-only
  divergence cannot print as two identical-looking strings.
- **`[known]` tagging**, so a clean run shows only NEW divergences.

New here:

- **`--target ARCH` cross mode.** There is no cross-gcc on this box (not even
  `gcc -m32` — no 32-bit multilib), so the oracle stays the native gcc run and
  each case is judged in two steps: pxx-native must match gcc first, then
  pxx-ARCH must match that same oracle. A case that already diverges natively is
  skipped rather than reported twice.
- **`lp64` tag** for cases whose output legitimately depends on the data model
  (`strtoul("-1")`, `atol("2147483648")`), so ILP32 does not produce false
  divergences.

## What it found

Native, first run — four crtl bugs, all fixed:

| | |
| --- | --- |
| `isprint` | used the whole space class, so `isprint('\t')` was true — every "safe to echo / needs escaping" test passed the control characters |
| `fread` | one `read()` call, no loop (a short read on a pipe/socket lost data) and never set the EOF flag, so `while (!feof(f))` did not terminate on the flag it tests |
| `strftime` | on overflow returned the TRUNCATED length instead of 0, handing back `"200"` as a year |
| `strtol`/`strtoull` | `"0x"` with no hex digit consumed the `x`; and "no conversion" left endptr past the whitespace/sign it had speculatively eaten instead of back at the start |

`--target i386`, first run — two more, in different lanes:

| | |
| --- | --- |
| `__pxx_exit` | `exit_group` hardcoded to **231**, x86-64's number. On i386/arm32 that is `fgetxattr`; on aarch64 it is not exit_group either. So C's `exit(3)` quietly failed an xattr call and the process exited **0** — every cross-target program reporting failure through `exit()` reported SUCCESS. Fixed here (Track B, `lib/rtl/pxxcio.pas`); `return 3` from `main` was unaffected, which is why nothing caught it. |
| varargs width | a bare pointer difference passed inline to a variadic function pushes 8 bytes on 32-bit and shifts every later argument. Filed as [[bug-a-pointer-difference-as-vararg-pushes-8-bytes-on-32bit]] — Track A, not fixed here. |

Plus a harness bug in `tools/run_target.sh`: the i386 native-exec path sent the
program's stderr to `/dev/null`, so every i386 run silently lost its
diagnostics — including for `tools/run_c_conformance.sh`, which compares
combined stdout+stderr. Fixed (and *not* by buffering it to a file and replaying
it: that reorders it against stdout, and the interleaving is part of what
callers compare).

## Traps this harness walked into — worth knowing before adding a case

Twice the tool reported a divergence that was the *case*, not the compiler, and
both times gcc was producing garbage too:

1. `printf("%ld %d\n", strtol(s, &e, 0), (int)(e - s))` — the call and the read
   of what it sets in one argument list is unspecified order, and gcc really
   does evaluate `e - s` first. Same shape as reading `errno` inline.
2. `printf("%ld %d\n", ftell(f), fgetc(f))` — `fgetc` moves the position, so the
   printed `ftell` depends on evaluation order. pxx orders arguments differently
   on arm32/aarch64 than on x86-64, all of it legal, which made it look like a
   cross-target bug.

**Sequence the calls; never read a side effect in the argument list that causes it.**

## Status

Clean on native, i386, arm32 and aarch64 — 0 new divergences, with the two filed
32-bit bugs tagged `known`.

## Gate

`tools/gcc_diff_probe.sh` exits 0; `gate.sh quick` + `gate.sh lib` green;
c-testsuite 219/0/1 native and i386.
