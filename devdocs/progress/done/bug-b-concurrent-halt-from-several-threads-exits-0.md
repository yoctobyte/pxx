---
summary: "DIAGNOSED, handed to A. Halt(n) on x86-64 and arm32 emits `exit` (thread exit), not `exit_group` — so in a multithreaded program it kills only the calling thread and the process status is decided by whichever thread exits LAST. A fatal then reports SUCCESS at random. i386, aarch64 and riscv32 already emit exit_group and three of them say so in a comment; x86-64 is the odd one out and is the primary target. Two-line fix in compiler/ir_codegen.inc and ir_codegen_arm32.inc."
track: A
prio: 60
type: bug
status: done
owner: frank-optimize
blocked-by: []
---

# `Halt` from several parallel-for workers at once can exit 0

Found while building the reactor-exhaustion guard in
[[bug-a-the-17th-thread-silently-aliases-reactor-slot-0]]. The guard needed to
die loudly; `Halt(216)` was the obvious body, mirroring `SpawnSized`'s `MAX_CO`
arm forty lines below it. It turned out not to be reliable, so that arm ships
calling `exit_group` directly and this ticket records what was left behind.

## Observed

`lib/rtl/scheduler.pas`'s exhaustion arm, built `-dPXX_SCHED_TINY_REACTORS`
(`MAX_REACTORS` = 2) so N parallel-for workers are refused a reactor. Each
refused worker printed one line and called `Halt(216)`. Same binary, same
width, repeated:

| workers | exit statuses |
| ---: | --- |
| 3 | 216 216 216 |
| 4 | **0 216 0** |
| 8 | **0 0 0** |
| 20 | 216 216 216 |

Replacing the body with `exit_group(216)` gives **216 in 30/30** runs across 3,
4, 8, 20 and 64 workers, which is what shipped.

**Why this matters beyond the one arm:** a fatal whose exit status is sometimes
0 reports SUCCESS to whatever ran it. Every harness here reads exit status.

## What is NOT the cause — the obvious repro does not reproduce

Six plain `palthread` threads, each calling `Halt(216)` immediately, with no
parallel-for anywhere:

```pascal
uses palthread;
procedure Body(arg: Pointer); begin Halt(216); end;
{ 6 x PalThreadCreate(Body) then PalThreadJoin }
```

**Exit 216 in 6/6 runs** — and `main reached the end` printed each time, so the
recorded status survives main's normal completion. So it is not "concurrent
`Halt` races": something about halting from inside a **parallel-for worker**,
during **reactor attachment** (i.e. very early in the worker's life, when all
workers are tightly synchronised at startup), is involved.

That is as far as it was taken. Reproduced, bounded, **not diagnosed** — the
lane may well be A (the `Halt` site is compiler-emitted: a call to
`__pxx_run_finalizers` and then the epilogue's exit, see `EmitProgramEpilogue`)
rather than B. Filed under B because the reproduction lives in `lib/rtl` and B
found it; **re-file to A without ceremony if the epilogue turns out to own it.**

## Two related facts worth having before starting

- **`Halt`'s exit path joins the worker threads.** Two attempts to serialise the
  fatal so only one thread called `Halt` both HUNG (exit 124 under `timeout`, at
  4, 8 and 20 workers): holding the attach spinlock across the fatal, and
  releasing it but parking the losing threads. A parked thread is one the join
  waits on forever. Whatever the fix, it has to survive that.
- **`SpawnSized`'s `MAX_CO` guard is the same shape and still uses `Halt`.** It
  was measured at two concurrently-refused workers and exited 216, so it is not
  observed broken — but nothing makes it structurally safer, and it is the
  natural second instance to check once the mechanism is known.

## Method note

The first pass at this table sampled each width **once**, produced 216 / 0 / 0,
and got written up as a deterministic rule — "one refusal reports correctly, two
or more exit 0" — which is wrong, and had already reached a source comment
before re-running destroyed it. One sample per cell reads exactly like a
measurement. Repeat every cell of a race's table before drawing a conclusion
from its shape.

---

## DIAGNOSED — 2026-08-29, by `frankB` (Track B). Retracked **B → A**, handed off.

Filed by me as "reproduced, not diagnosed". It is now diagnosed, and it is not a
`lib/rtl` defect at all: it is two lines of backend codegen. **Track B does not
edit `compiler/**`, so this is a hand-off, not a fix.**

### Root cause

`Halt(n)` is compiled to the **`exit`** syscall, which terminates *only the
calling thread*. `compiler/ir_codegen.inc:8802`:

```pascal
if IRA[node] <> -1 then
begin
  IREmitNode(IRA[node]);
  EmitB($48); EmitB($89); EmitB($C7);   { mov rdi, rax }
  MovRaxImm(SYS_EXIT);                  { <-- 60 = exit, NOT 231 = exit_group }
  EmitSyscall;
end
else
  EmitExit(0);
```

`defs.inc:1294-1295` defines **both** numbers — `SYS_EXIT = 60` and
`SYS_EXIT_GROUP = 231` — and this arm reaches for the wrong one. Confirmed in
the emitted binary, not only in the source: the sequence is
`48 89 c7 | b8 3c 00 00 00 | 0f 05`, i.e. `mov rdi,rax; mov eax,0x3c; syscall`.

**And the correct answer is already written down twice.** The `else` branch one
line below calls `EmitExit`, whose definition at `compiler/emit.inc:365` carries
this comment:

> `exit_group, not exit: terminate every thread. A bare exit (60) only ends the
> calling thread, so a program that started worker threads (e.g. via gtk_init /
> GLib) would leave the process alive after main returns.`

`Halt` with no argument obeys that. `Halt(n)` does not.

### Five hand-written arms for one concept; two drifted

| backend | `Halt(n)` emits | |
| --- | --- | --- |
| **x86-64** (`ir_codegen.inc:8802`) | `SYS_EXIT` = 60 = **exit** | **wrong** |
| i386 (`ir_codegen386.inc`) | `mov eax, 252` = exit_group, *commented as such* | correct |
| aarch64 (`ir_codegen_aarch64.inc`) | `movz x8, #94` = exit_group | correct |
| **arm32** (`ir_codegen_arm32.inc`) | `mov r7, #1` = **exit** | **wrong** |
| riscv32 (`ir_codegen_riscv32.inc`) | `addi a7, x0, 94  (exit_group)`, *commented* | correct |
| xtensa | parks in a self-loop (bare metal) | n/a |

Three arms name `exit_group` in a comment. The two that are wrong are x86-64 —
the primary target, where it matters most — and arm32. This is
`normalise-dont-special-case.md` exactly: one concept, six hand-rolled copies,
and the drift lands on the arm nobody re-derived because it is the one that
"obviously works".

### Why it presents as a random exit status

Measured, not inferred:

- A worker calling `Halt(7)` makes **main** exit with **7** — so `Halt` also
  records the code where the program epilogue reads it.
- The process's status is set by whichever thread **exits last**.
- Threads finishing normally exit **0**.

So the fatal's status survives only if the last thread out is one that saw it.
That is why the two reproductions disagreed and why my first table was wrong:

| shape | last thread out | result |
| --- | --- | --- |
| 6 plain `palthread` threads, each `Halt(216)`, **main joins them all** | necessarily main | 216, 6/6 — deterministic |
| parallel-for workers refused a reactor, some `Halt`, others finish | whoever wins the race | **0 or 216, run to run** |

`strace -f` shows it directly: in the failing runs the final syscall is
`exit(0)` from a worker that finished normally, long after another worker
already announced the fatal. Nothing is lost or overwritten — the 216 simply was
not the last word.

**This also explains why the obvious minimal repro did not reproduce**, which is
what stalled the first pass: explicit `PalThreadJoin` *orders* the exits and
makes main last by construction, so the very act of writing a clean repro
removes the race.

### Scope — wider than the arm that found it

Every `Halt(n)` in a multithreaded x86-64 or arm32 program: `SpawnSized`'s
`MAX_CO` guard, every library error path, every `Halt(1)`. In a single-threaded
program the two syscalls are equivalent, which is why this has survived — and
why `--threadsafe` is the only place it bites.

### Fix

Emit `exit_group` for `Halt(n)` on x86-64 and arm32, matching the other three
hosted backends and `EmitExit`'s own stated rule. On x86-64 that is
`MovRaxImm(SYS_EXIT_GROUP)` — the constant already exists in `defs.inc`. On
arm32, `mov r7, #248` instead of `#1`.

**Regression test:** a `--threadsafe` program where a *non-main* thread calls
`Halt(n)` while another thread outlives it must exit `n`. The existing
`test_sched_reactor_exhaustion` cannot serve — `lib/rtl/scheduler.pas` now works
around this by calling `exit_group` through `__pxxrawsyscall` directly, so it
would pass with the bug present. **When this is fixed, that workaround should be
reverted to a plain `Halt(216)`** and the test will then cover both.

---

## FIXED 2026-08-29 by `frank-optimize` (Track A) — as one arm, not two constants

frankB's diagnosis was exactly right and is not restated here. What follows is
what the fix did differently from what the ticket proposed, and why.

### The ticket proposed two edited constants. That would have left the sixth copy free to drift.

The ticket's own table is the argument against its own fix shape: **five
hand-written arms for one concept, two of them drifted, and three of the correct
ones carry a comment saying `exit_group` — a comment is what you write when the
rule has nowhere to live.** Editing 60 to 231 and 1 to 248 repairs today's two
and leaves the next backend author to re-derive the rule from scratch. The
riscv32 arm shows what that costs: it had *already noticed* the gap, writing
*"EmitExit's own encodings only cover a constant"*, and hand-rolled around it
instead of closing it. **That sentence is what a missing abstraction looks like
from inside the fifth copy of it.**

So the fix is `EmitExitReg` in `emit.inc`, placed beside `EmitExit` and sharing
its reasoning, with every backend's `AN_HALT` arm reduced to *evaluate the code,
then call it*. The rule now has one home.

Kept adjacent to `EmitExit` rather than folded into it, deliberately: the
constant form materialises the code itself, this one must not touch the register
the caller has just filled. Two behaviours, one rule, and the rule stated once.

### The emitted diff is exactly the prediction and nothing else

Isolated against a compiler carrying all of the session's other work, so the
aarch64 changes from an unrelated ticket do not contaminate it:

| target | change |
| --- | --- |
| x86-64 | 8 bytes, every one `0x3C` → `0xE7` (60 → 231), i.e. eight `Halt` sites |
| arm32 | 8 bytes, every one `0x01` → `0xF8` (1 → 248) |
| i386, aarch64, riscv32 | **byte-identical** |

A refactor that moves five arms into one routine and changes the output of
exactly the two that were wrong is the strongest evidence available that the
normalisation preserved the four it touched.

### The workaround revert is half the fix, and it was TESTED, not assumed

`lib/rtl/scheduler.pas` is a plain `Halt(216)` again. This mattered more than
tidiness: while the workaround stood, `test_sched_reactor_exhaustion` passed
**whether or not the compiler was correct.**

| | exit status, 10 runs |
| --- | --- |
| reverted source + **fixed** compiler | **216**, 10/10 |
| reverted source + **pre-fix** compiler | **0**, 10/10 |

The test now guards the bug it was written for. A workaround installed while a
bug is open becomes a blindfold the moment the bug closes.

**It was not assumed safe.** The scheduler comment recorded a second measured
fact — *Halt's exit path JOINS the worker threads*, and two attempts to
serialise the fatal HUNG. A revert could plausibly have reintroduced a hang
rather than a wrong status, so it was run before it was believed: 10/10 clean,
no hang. The hang came from *serialising* the fatal (holding `regLock`, parking
the losers), which this arm does not do; that half of the comment is preserved
because it is still true and still load-bearing.

### The regression test is deliberately NOT minimal — this is the transferable part

`test_halt_from_worker_thread`. The tidy repro **cannot fail**: N threads each
calling `Halt(n)` with main joining them all makes main last *by construction*,
so the recorded status survives whichever syscall `Halt` used. Six such threads
exited 216 **6/6 with the bug fully present**, and that green is what stalled the
first pass at "reproduced, not diagnosed". The 6/6 was not weak evidence — it was
strong evidence for the wrong proposition.

**When the defect IS the disorder, minimisation is the one technique guaranteed
to fail.** So the test does the opposite: nobody joins the worker, and it asks
whether the process **dies** rather than what status it reports. That second
change is what makes it deterministic — 10/10 exit 216 with the fix, 10/10 print
the marker and exit 3 without, on x86-64 and arm32 alike — where the original
investigation had a three-samples-per-cell table of a race that read as a rule.

The ticket's own method note said *"repeat every cell of a race's table before
drawing a conclusion from its shape."* The stronger move is available here:
**find the question whose answer is not a race.**

### Verification

| check | result |
| --- | --- |
| self-host fixedpoint | converged, `bded6edfa55e` |
| `Halt(7)` on x86_64 / i386 / aarch64 / arm32 / riscv32 | exits 7 — the refactor's own guard |
| threaded repro, x86-64, fixed / pre-fix | 216 3/3 · marker + exit 3, 3/3 |
| threaded repro, arm32 under qemu-arm, fixed / pre-fix | 216 3/3 · marker + exit 3, 3/3 |
| `test_sched_reactor_exhaustion` with the revert, fixed / pre-fix | 216 10/10 · **0 10/10** |
| emitted-byte diff | only the syscall numbers, only on the two broken targets |

### Left alone

`SpawnSized`'s `MAX_CO` guard, which the ticket flagged as the natural second
instance, needed no change — it already called `Halt(216)`, and that call is now
correct for the same reason every other one is. It was never separately broken;
it was the same bug seen from a place that happened not to race.

### Retracked

Filed **B**, fixed under **A** as the ticket instructed — the defect was
compiler-emitted codegen throughout, and the only `lib/**` edit is the removal of
a workaround the ticket itself scheduled for removal.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
