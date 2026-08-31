---
slug: bug-a-the-exception-shadow-chain-is-process-wide-so-two-threads-crash
track: A
prio: 70
type: bug
status: working
owner: frankS
blocked-by: []
summary: "MEASURED: 18 of 22 two-threaded runs CRASH -- mostly SIGSEGV (139), sometimes exit 217 with an exception that escaped its own `try`. The single-threaded control is clean in 12 of 12 runs of the SAME BINARY, in the same process, moments earlier. `BSS_EXC_TOP` is the setjmp shadow-chain HEAD and is one process-wide slot, so two threads push and pop try-frames onto one chain and a raise longjmps into the other thread's dead frame. This is worse than the signal-slot race fixed in 47439504c: that produced wrong VALUES, this terminates the process. Allocation-free repro, so it is not the heap lock. Scope is ~64 references to BSS_EXC_TOP across 14 files and all seven backends, which is most of the work. The COROUTINE population is NOT an obstacle -- checked, CoSwitch already saves and restores the head across a switch on every target -- and the real open question is COST: the head is touched on every try entry and exit, unlike the signal fields which are touched once per delivered signal."
---

# The exception shadow chain is process-wide, so two threads crash

- **Found:** 2026-08-31 by frankA, at frankS's suggestion after they fixed the
  signal-field twin ([[bug-a-the-parked-signal-slots-are-process-wide-and-race-across-threads]],
  `47439504c`). They deliberately did not assert it from the shape; this is the
  repro they asked for.

## Measured

Two threads, each running an identical loop of `try raise 7 except ... end`,
100000 iterations. **Allocation-free on purpose**: an exception carrying an
object would take the heap lock on every raise, serialising the threads and
hiding the interleaving under test.

```
phase 1, single-threaded (same binary, same process, seconds earlier):
  hitsA=100000  wrongA=0  escaped=0        clean in 12 of 12 runs

phase 2, two threads:
  18 of 22 runs FAIL
    rc=139  SIGSEGV                         (dominant)
    rc=217  "Unhandled exception"           an exception escaped its own try
```

The built-in control is the point: **the failure needs only the second thread.**
Nothing else about the run changes.

It is a race, not a deterministic break — N=100 and N=10000 have both passed,
N=1000 has failed. Do not read a single green run as a fix.

## Why

`EnableExceptionRuntime` (`pasparser_proc.inc:3003`) allocates four
**process-wide** slots:

```pascal
BSS_EXC_TOP := BSSSize; ...   { the setjmp shadow-chain HEAD }
BSS_EXC_OBJ := ...            { the exception object }
BSS_EXC_CLS := ...
BSS_EXC_ADDR := ...           { the raise site }
```

`BSS_EXC_TOP` is not a status value like the signal fields — it is the **head of
the chain the unwinder walks**. Every `try` pushes a setjmp buffer onto it and
every exit pops it. Two threads share one head, so thread A's `try` links onto
thread B's frame, and a raise longjmps into a frame that belongs to the other
thread and may already be dead. That is why this crashes rather than merely
answering wrong.

(The allocation itself is fine and is NOT the `BSS_IO_OWNER` bug: it is
demand-driven and idempotent through `ExceptionUsed`, so every frontend reaches
it. Checked before filing.)

## Why it is filed and not fixed

The signal fix moved **four** fields with four writers. This is:

| | refs |
| --- | --- |
| `BSS_EXC_TOP` | ~64, across 14 files — all seven backends, plus `coroutine_emit.inc` (20) |
| `BSS_EXC_OBJ` / `_ADDR` | ~41 more |

### Coroutines are NOT an obstacle — checked, 2026-08-31

My first filing said they were, on the reasoning that a coroutine switches stacks
so "the current thread's chain" and "the current coroutine's chain" are different
questions. **That was reasoning from the construction I could see, and it is
wrong.** frankS pointed out the argument and named the one thing to check
instead: does the switch primitive save and restore the head?

It does, on every target. `CoSwitch` (`coroutine_emit.inc:34-39` on x86-64, and
the i386/aarch64/arm32 twins at :60/:65, :85-98, :115-126) pushes
`[BSS_EXC_TOP]` onto the outgoing stack with the callee-saved set and pops it
back from the incoming one — its header at :16 says so outright.

So a coroutine that yields inside a `try` carries its chain head with its stack,
there is no second bug, and those 20 references need **no change**: move the head
to per-thread storage and they manipulate the per-thread head with identical
semantics. A coroutine never migrates between threads, so it lives entirely
inside one cell of a strictly finer partition.

(If the switch had NOT saved it, that would have been a second bug — present
today, orthogonal to threads, and neither fixed nor worsened by this one. The
right axis then would have been per-STACK rather than per-thread, since a thread
has a stack and a coroutine has a stack and one rule covers both.)

### The real open question is COST, and it does not transfer from the signal fix

frankS's own caveat, and it is the only serious objection: their four fields are
touched **once per delivered signal**, so a `mov rax, gs:[0]` in front of each is
free. `BSS_EXC_TOP` is touched on **every try entry and every try exit**, in code
the compiler itself runs constantly. *"It costs nothing" was a claim about a
population, not about the mechanism.*

**Measure a try/except-heavy loop before and after.** If it bites, the answer is
to hold the head in a register across a procedure, not to abandon per-thread
storage.

#### The BEFORE is measured. Two numbers, because they bound the cost from
#### opposite ends and neither alone is the answer.

Compiler `1655056bd7cf`, interleaved, min-of-3 (never a mean, never
before-then-after -- the box is shared).

**Ceiling -- a microbenchmark that is nothing but the mechanism.** 20M calls to
a procedure whose body is a non-raising `try`, against an identical procedure
without one:

```
round 1:  try=0.17s   notry=0.08s
round 2:  try=0.17s   notry=0.08s
round 3:  try=0.17s   notry=0.08s
```

**~4.5 ns per call, and it roughly DOUBLES a trivial call.** That is the
worst-case denominator: a per-thread head adds a load to each of the two touches
in that 4.5 ns, so measured against *this* benchmark the change will look
expensive. It is also the least realistic workload in the repo -- nothing
otherwise does 20M calls to an empty guarded proc.

**Floor -- the real population, which is what the objection is actually about.**
A full single self-compile of `compiler/compiler.pas`:

```
round 1: 14.67s   round 2: 14.62s   round 3: 14.47s
```

**14.47s is the number to beat after the change.** Use this one for the
accept/reject call, not the microbenchmark.

##### An enumeration error worth recording, because it nearly set the wrong denominator

Asked how try-heavy the compiler is, my first count said **9** `try` sites in
`compiler/**` and I was about to conclude the self-compile was the wrong
population entirely. The grep was `^\s*try\b` -- it only matches `try` as the
*first token on a line*, so every `try` following code on its line was invisible.
The real count is **~164** in `compiler/`, plus 9 in `lib/rtl` and 1 in
`lib/pcl`. Off by 18x, in the direction that would have discarded the only
realistic benchmark available. *(Enumerate from the artefact; a grep counts one
spelling.)*

Note the two counts measure different things and only one is the cost driver:
the chain happens at **proc entry for procs containing a try**
(`ir_codegen.inc:12478`), so the runtime cost scales with **calls to those
procs**, not with the number of try sites. 164 sites is evidence the workload is
representative, not a cost estimate.

### The target story is cleaner here than for signals

`palthread` compile-errors at the `__pxxclone` call site off x86-64, so **the
targets with no TLS block are exactly the targets with no threads.** There is no
arch where per-thread storage is needed and unavailable — which could not be said
of the signal fields.

And TLS is x86-64-only (`EmitTlsMainInstall`), so the fix helps one target and
the other four keep the bug — the same honest limit frankS recorded.

## Note

`--threadsafe` + exceptions is **not** documented as unsupported anywhere, and
nothing refuses it. Until this is fixed, a `--threadsafe` program that raises on
more than one thread is unsound; a refusal, or a documented limit, may be worth
more than nothing while the real fix waits.

Repro kept at `$SCRATCH/excrace.pas` (frankA's session); it is 50 lines and
trivially rebuilt from the description above.
