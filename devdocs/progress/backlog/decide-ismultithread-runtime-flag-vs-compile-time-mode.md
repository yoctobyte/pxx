---
track: U
prio: 55
type: decide
summary: "Delphi/FPC do not detect threading at compile time at all — they always emit the lock and skip it at runtime on a global IsMultiThread boolean. Measured here: the branch costs +5% over an unlocked refcount where an unconditional lock costs +276%. That dissolves the auto-detect question and would let TThread live in Classes unconditionally"
---

# `IsMultiThread` at runtime, instead of a compile-time mode?

- **Type:** decide — Track U (design direction; the work is Track A)
- **Opened:** 2026-08-09
- **Filed by:** Track B, from the user's question "could the compiler detect
  whether the application uses threads and enable `--threadsafe` automatically?"
  The honest answer turned out to be that the premise is avoidable.

## What Delphi and FPC actually do — measured, not recalled

The question included "not sure how Delphi solves it, maybe they never optimize
for no-threads, maybe they prescan". Neither. FPC 3.2.2 is on this box, so it
was measured rather than guessed:

```pascal
writeln(IsMultiThread);          { FALSE }
t := TW.Create(True);
writeln(IsMultiThread);          { TRUE — set at Create, before Start }
```

`IsMultiThread` is a plain `longbool` in `rtl/inc/systemh.inc:694`, initially
FALSE, set TRUE when a thread is created and never reset. The refcount
primitives then branch on it. From FPC's own x86-64 assembler
(`rtl/x86_64/x86_64.inc:678`), comment included:

```asm
function declocked(var l : longint) : boolean;assembler; nostackframe;
  asm
     { this check should be done because a lock takes a lot }
     { of time!                                             }
     cmpl       $0,IsMultithread(%rip)
```

So there is **no compile-time detection anywhere in the design**. The locking
code is always compiled in; the lock is skipped at runtime while the program is
single-threaded. Delphi shares this lineage and this mechanism.

## What the branch costs, versus the lock

200M iterations, `clock_gettime(CLOCK_PROCESS_CPUTIME_ID)`, gcc -O2:

| refcount path | time | vs floor |
| --- | --- | --- |
| always `lock incl` | 1.454 s | **+276%** |
| `cmp` flag, single-threaded path taken | 0.407 s | **+5%** |
| plain `incl` (floor) | 0.387 s | — |

The branch is perfectly predicted — the flag never changes in a single-threaded
run — so it recovers about 95% of what the lock costs. For comparison, pxx's
current all-or-nothing `--threadsafe` measured **+14%** on a string/heap-heavy
Pascal benchmark; that whole 14% is what this design would mostly reclaim while
still being thread-safe.

## Why this dissolves the question that prompted it

Every hard part of "auto-detect threading" was a consequence of the mode being a
COMPILE-TIME fact:

- it must be known **before lexing** (`{$threadsafe on}` is already rejected on
  i386/aarch64/arm32 because "the softlock define is applied before lexing");
- detection is undecidable in general, and the dangerous direction is the false
  negative — unlocked heap under real concurrency;
- it is circular with the `PXX_THREADSAFE` ifdef, since `TThread` would only
  exist when the flag is already on;
- and `uses cthreads`, which I had recommended as the trigger, is a **Unix-FPC
  hack that Delphi sources do not have** (user, 2026-08-09) — so it would have
  covered only half the real-world corpus. That objection is what led here.

With a runtime flag none of it applies. Nothing is detected, because nothing
needs to be: the program is single-threaded until the moment it creates a
thread, and that moment sets the flag.

## What it would mean for pxx

- `TThread` lives in `Classes` **unconditionally** — no ifdef, no define, and
  `uses Classes` behaves as it does on FPC and Delphi.
- The `__pxxclone` parse-time gate loses its rationale for the heap/ARC/I-O
  part and can go, along with the whole family of problems in
  [[decide-threadsafe-gate-is-reach-based-not-use-based]].
- `--threadsafe` survives but INVERTS: instead of "make this build thread-safe",
  it becomes something like `--no-threads` — strip even the branch and the lock
  blobs — for microcontrollers and size-critical builds where you know there is
  no threading. That keeps the reasons the flag exists (user, 2026-08-09: MCU
  targets and single-threaded applications) while making the safe thing the
  default.

## Cost and open questions

- **Not a small change.** It touches the x86-64 codegen-emitted lock blobs, the
  softlock paths on the other four targets, the heap allocator and the
  `IR_IO_LOCK` console path — every site that currently keys off
  `ThreadSafeMode` at compile time keys off a runtime global instead.
- **Code size grows** in the default build: the lock paths are always present.
  That matters for MCU targets, which is exactly what the inverted flag is for.
- **Who sets the flag, and when.** FPC sets it at `TThread.Create`, before the
  OS thread exists — the ordering that makes it safe. pxx would set it in
  `PalThreadCreate` / `BeginThread` / `TThread.Create`, and must do so *before*
  the child can run.
- **The flag is never reset**, deliberately: a program that has ever been
  multi-threaded may still hold shared data.
- **Does it interact with `PXX_TS_HARDLOCK`/`SOFTLOCK`?** Those select which
  lock implementation is used; both would gain the same guard.

## Recommendation

Land [[feature-a-pxx-threadsafe-conditional-define]] first regardless — it is a
one-line compiler change that unblocks `TThread` in `Classes` now, and it is not
wasted work if this lands later (the ifdef simply becomes unnecessary and comes
out).

Then decide this one on its own merits. It is the design Delphi and FPC both
converged on, the measurement says the branch is nearly free, and it removes a
whole class of questions rather than answering them. The counter-argument is
code size on microcontrollers, and the inverted flag answers that — but it is a
real piece of Track A work across five targets, not a quick win.
