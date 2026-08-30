---
slug: feature-s-the-xtensa-row-of-the-posix-syscall-table
track: B+S
prio: 40
type: feature
blocked-by: []
status: done
summary: "14 of 129 cross programs fail to COMPILE for hosted xtensa on `undefined variable (SYS_openat)` / `(SYS_gettid)` — lib/rtl has per-arch syscall-number blocks for x86-64/i386/aarch64/arm32/riscv32 and no xtensa row anywhere. Measuring the table (not recalling it) splits the 14 cleanly in two: 8 are exactly the missing table and are this ticket; 6 are the scheduler and are blocked on a Track A change, and giving them numbers WITHOUT it would replace a compile error with a jump into code that was never emitted."
owner: frankS
---

# The xtensa row of the POSIX syscall table

## Files this ticket touches — declared before starting

| file | lane | why |
| --- | --- | --- |
| `lib/rtl/platform/posix/platform_backend.pas` | **B** | add the `{$ifdef CPU_XTENSA}` constant block; define `PAL_GENERIC_SYSCALLS`; introduce `SYS_exit` so the hardcoded `93` stops being a literal |
| `Makefile` (`test-xtensa` target only) | B | wire the newly-passing rows |

**Nothing else.** In particular this ticket does **not** touch
`lib/rtl/scheduler.pas`, `lib/rtl/palthread.pas`, or `compiler/**` — see
*The split* below for why the first two are deliberately left failing.

`lib/pcl` is frankB's (tkinter pad); `lib/rtl/platform` is clear.

## Gate — and the one place B's gate cannot reach, stated rather than glossed

B's gate: build with `$(PXX_STABLE)`, never rebuild the compiler, `make lib-test`.
That is the gate **against breaking the five existing targets**, and it is the
one that matters, because that is the whole regression surface of this change.

It is not reachable for the xtensa half: `pinned` predates the xtensa backend
work of 2026-08-29/30 and cannot produce a working xtensa binary at all, so
verifying that the 8 programs now compile *and match the x86-64 oracle*
necessarily uses the HEAD compiler. Both halves are run; they are run with
different binaries, and each result names which.

## The numbers were MEASURED, not recalled

xtensa Linux has **its own** syscall numbering — not asm-generic, not i386's.
Read=12, write=13, exit=118. Recall would have been wrong.

Method: an *inert identification probe*. One syscall per process, number read
from stdin, every argument `2147483647` — chosen so the call cannot do anything
whatever it turns out to be: unmapped as a pointer (EFAULT), out of range as an
fd (EBADF), nonexistent *and positive* as a pid so it can never mean a process
group or "every process" (ESRCH), invalid as a signal, wrong as reboot's magic.
Run under `qemu-xtensa -strace`, which prints the resolved name.

**One-syscall-per-process is load-bearing.** The first attempt scanned many
numbers in one process and reported `mmap2=79`; the repo's established value is
80. qemu segfaults the process on a bogus `bind`, the restart loses a number,
and every subsequent row is off by one — a table that is *plausible and wrong*,
which is this repo's expensive shape. The single-shot form reproduces all five
independently-established anchors exactly: `read=12`, `write=13`, `mmap2=80`,
`exit=118`, `exit_group=119`.

## The split — 14 rows, two different defects

`undefined variable` is reported per identifier, so grouping the 14 by *which*
identifier is undefined separates them without guessing:

**8 rows — the missing table, and nothing else.** `lib_bignum_ops`,
`test_cross_float_const`, `test_ctor_string_literal_arg`,
`test_overflow_checks_qplus`, `test_overflow_qplus_narrow`,
`test_signal_default_revert_b336`, `test_signal_handler_callback_b336`,
`test_variant_comparison_coerces_a_stringy_operand`. Every one fails on the
same 19 names, all from `platform_backend.pas`'s block. None of them is *about*
syscalls — they are overflow checks, a variant comparison, a constructor
argument. They fail because the POSIX PAL is linked into every hosted program,
so a hole in the table stops programs that never call into it.

**6 rows — the scheduler, and they are NOT a table problem.**
`test_asyncecho`, `test_channel`, `test_reactor`, `test_scheduler`,
`test_scheduler_exc`, `test_timer` fail on `SYS_gettid` /
`SYS_epoll_create1` / `SYS_fcntl` from `lib/rtl/scheduler.pas`. Those numbers
are measurable too (`gettid=127`, `epoll_create1=275`, `epoll_ctl=19`,
`epoll_wait=18`, `fcntl=67`) — and filling them in would be the wrong move.

`scheduler.pas` needs three more things per target, and the third is A's:

1. an `epoll_event` layout (x86 packs it; everyone else pads to 8-align the u64);
2. a `SpawnSized` stack-priming block matching the target's `CoSwitch` pop order;
3. **a `CoSwitch` emitted by `compiler/coroutine_emit.inc`** — which covers
   x86-64, i386, aarch64, arm32 and refuses wasm32, and for xtensa (and
   riscv32) *falls through silently, on purpose*, per its own closing comment.

So on xtensa `CoSwitchAddr` is never set and `SpawnSized`'s `{$else}` chain
falls through to the **x86-64** frame layout. Supplying the syscall numbers
would turn six honest compile errors into six programs that build and jump into
code that was never emitted, priming a stack for the wrong architecture.

**The compile error is currently the only thing preventing that.** This is the
session's "a missing op hides every bug in the programs it stops from
compiling" running backwards: usually the block is hiding a defect and removing
it is pure gain; here the block *is* the guard, and removing it alone is a
regression wearing the costume of six more green rows.

→ filed as a Track A ticket. Not an extension of this one.

## The hardcoded `93`, which is `socket` on xtensa

`PalBackendVforkAndExec`'s failed-exec child path ends:

```pascal
{$ifdef CPUX86_64}          res := __pxxrawsyscall(60, 127, ...); {$endif}
{$ifdef CPU_I386}           res := __pxxrawsyscall(1,  127, ...); {$endif}
{$ifdef PAL_GENERIC_SYSCALLS} res := __pxxrawsyscall(93, 127, ...); {$endif}
{$ifdef CPU_ARM32}          res := __pxxrawsyscall(1,  127, ...); {$endif}
```

`93` is `exit` on the asm-generic table, which is what aarch64 and riscv32 use —
correct for both, and correct only by coincidence of them sharing a table. It is
keyed on `PAL_GENERIC_SYSCALLS`, which means "clone + dup3 + direct socket
syscalls" — a *calling shape*, not a numbering. xtensa fits that shape exactly
(no `fork`, no `vfork`, no `socketcall`; `clone=116`, `dup3=310`,
`socket=96`) and has completely different numbers. On xtensa, `93` is `socket`.

A child whose `execve` failed would open a socket and then fall out of the
`if pid = 0` block *as the child*, returning `pid` (0) to a caller that will
read it as "I am the parent, here is the child pid 0". Silent, and it only
happens on a failed exec.

Fixed by giving every arch a `SYS_exit` constant and deleting all four literals,
rather than adding an xtensa special case beside them. Each arch keeps the exact
number it had, so the five existing targets are byte-identical by construction.
This is an arm of the same defect in the same file — the table not covering
xtensa, wearing a literal instead of a constant — not an adjacent one.

## What is deliberately NOT special-cased

- **`SYS_lseek = 15`.** riscv32 needed a whole `PalBackendSeek` arm because its
  `62` is `_llseek` (5 args, result through a pointer). xtensa has *both*: plain
  `lseek` at 15 and `_llseek` at 17. The plain form takes the existing 3-arg
  `{$else}` path, so xtensa adds no arm. (32-bit `off_t`; the same bound the
  riscv32 comment already records for small offsets.)
- **`SYS_mmap = 80`** is `mmap2`, matching i386's `192` and arm32's `192`. The
  call sites already pass page-offset 0 and say "32-bit = mmap2".

## Result — measured, and it is ONE green row

`make lib-test` **green** (exit 0, 522 lines, `lib-test ok` against stable v393).

**The five existing targets are byte-identical, proved rather than argued.** A
program that actually reaches `PalBackendVforkAndExec` was compiled with
`$(PXX_STABLE)` for x86-64, i386, arm32, aarch64 and riscv32, before and after
the change, and `sha256sum` matches on all five. That is the whole regression
surface of the `SYS_exit` refactor, closed by construction.

xtensa, full 129-source differential, HEAD compiler `1bca19929e04` (a verified
self-host fixedpoint at `b0cf17b00`, sha differs from `pinned` — checked, not
assumed):

```
before   MATCH 96   DIFF 7   CFAIL 25   X64SKIP 1
after    MATCH 97   DIFF 8   CFAIL 23   X64SKIP 1
exactly two rows moved, both off CFAIL, zero regressions
```

**One new green row**, not eight. That is the honest number and it is the
interesting one:

| source | was | is |
| --- | --- | --- |
| `test_signal_default_revert_b336` | CFAIL | **MATCH** — wired into `test-xtensa` |
| `test_cross_float_const` | CFAIL | DIFF — compiles, runs, **bus errors** |

The other twelve did not become green and did not stay one problem. They became
**five distinct, individually filed defects**, none of which existed as a ticket
this morning because no program could reach the code that contains them:

| n | defect | ticket |
| --- | --- | --- |
| 5 | `call0` displacement > ±512 KiB, no veneer — xtensa cannot build a program over ~512 KiB of code, and 512 KiB is small here | [[bug-a-xtensa-cannot-build-a-program-over-512-kib-of-code-call0-has-no-veneer]] |
| 6 | the scheduler: no `CoSwitch` for xtensa, left failing ON PURPOSE | [[feature-a-coswitch-for-xtensa-and-riscv32-the-scheduler-has-no-context-switch-there]] |
| 1 | no `IR_SET_SIGNAL` arm (riscv32 has one) | [[bug-s-xtensa-has-no-ir-set-signal-arm-riscv32-does]] |
| 1 | a `Double` typed const misaligns the next const array in the data section — **arm32 has it too, silently** | [[bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section]] |

Each was bisected to a boundary before being written down. The last one is worth
the most: the victim array is `array of Int64`, an `Int64` scalar in the same
position does not trigger it, a `var` array is unaffected, and the addresses were
**printed by the program** (`A @ 3 mod 8` on xtensa, `4` on arm32, `0` on the
four correct backends) rather than reasoned about from the emitter. Four
backends right and two wrong in the same direction by different amounts is the
signature of a bug in the shared alignment accounting, not in either arm — so
fixing it under xtensa would have left arm32 quietly broken.

## The generalisation this ticket is really about

*A missing thing hides every bug in the programs it stops from compiling* — the
fifth and sixth payouts this session — plus its **inverse**, which is new:

> Sometimes the block IS the safety property. Filling in the scheduler's six
> syscall numbers is a two-line change anyone would read as obviously safe, and
> it would replace six honest compile errors with six programs that build and
> jump into a `CoSwitch` that was never emitted, from a stack primed with the
> x86-64 frame layout. The compile error was the only thing preventing that.

So the correct move on finding a hole in a table is not "fill the table". It is
**fill it, then look at what the hole was holding back** — and check, for each
row, whether the error was concealing a defect or preventing one.

The row this ticket adds to `test-xtensa` asserts the **exit status**, not
stdout: `test_signal_default_revert_b336`'s entire subject is dying by SIGTERM,
and its one line of stdout would match whether or not that happened. Adding it
as an `expect_same` on output would have been exactly the vacuous-green shape
[[chore-t-sweep-for-rows-that-assert-stdout-when-the-subject-is-an-exit-code]]
was filed about earlier tonight.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
