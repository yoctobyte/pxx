---
summary: "DIAGNOSED, handed to A. Halt(n) on x86-64 and arm32 emits `exit` (thread exit), not `exit_group` — so in a multithreaded program it kills only the calling thread and the process status is decided by whichever thread exits LAST. A fatal then reports SUCCESS at random. i386, aarch64 and riscv32 already emit exit_group and three of them say so in a comment; x86-64 is the odd one out and is the primary target. Two-line fix in compiler/ir_codegen.inc and ir_codegen_arm32.inc."
track: A
prio: 60
type: bug
status: working
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
