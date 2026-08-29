---
track: B
prio: 75
type: bug
blocked-by: []
summary: "lib/rtl/scheduler.pas CurR() falls back to slot 0 when all MAX_REACTORS=16 reactors are in use — `slot := 0` is the initializer and nothing checks for exhaustion. The 17th OS thread silently adopts a live thread's reactor, the two share coroutine state, and the result is memory corruption reported as 'coroutine stack overflow (canary clobbered)'. Invisible on every 12-core box; deterministic above 19 threads. Found on seven (24 cores) 2026-08-29."
status: done
owner: frankB
---

# The 17th thread silently aliases reactor slot 0

`test/test_async_parallel_compat.pas` is **green on plexus and red on seven**, and
the difference is not the tree — it is the core count.

## The defect

`lib/rtl/scheduler.pas:199` — `CurR()` finds this thread's reactor, or claims a
free one:

```pascal
  slot := 0;
  for i := 0 to MAX_REACTORS - 1 do
    if reactors[i].used = 0 then begin slot := i; Break; end;
  reactors[slot].tid  := me;
  reactors[slot].used := 1;
```

`slot := 0` is an initializer, not a choice. **When every one of the 16 reactors
is already `used`, the loop matches nothing and the fallthrough claims slot 0 —
which belongs to a live thread.** `reactors[0].tid` is overwritten, `coCount` and
`curCo` are reset under the owner's feet, and two OS threads then drive one
reactor's coroutine table. What surfaces is a clobbered stack canary, attributed
to the coroutine rather than to the aliasing.

`MAX_REACTORS = 16` is commented *"one per OS thread / core"*, so the ceiling is
a statement about the host, and nothing enforces it.

**The correct pattern is 40 lines below, for the sibling limit** (`:254`):

```pascal
  if id >= MAX_CO then
  begin writeln('fatal: scheduler out of coroutine slots (MAX_CO)'); Halt(216); end;
```

`MAX_CO` exhaustion is loud and fatal. `MAX_REACTORS` exhaustion is silent and
corrupting. Same file, same kind of limit, opposite failure modes — which is
what makes this a defect rather than a missing feature.

## Measured — `taskset` is the whole experiment

One binary, one box, one build (`./compiler/pascal26 --threadsafe`, self-host
fixedpoint `converged after 2 round(s)`, sha `b2dff2c3cbf9` ≠ pinned). Only the
CPU affinity mask changes:

| cores | runs OK |
| ---: | --- |
| 4 | 10/10 |
| 12 | 10/10 |
| 13 | 12/12 |
| 14 | 12/12 |
| **16** | **12/12** |
| **17** | **4/12** |
| 18 | 2/12 |
| 19 | 1/12 |
| 20 | 0/12 |
| 24 | 0/12 |

Failure output:

```
fatal: coroutine stack overflow (canary clobbered)
```

The cliff sits exactly at `MAX_REACTORS`, and the probabilistic band from 17-19
is what an aliasing bug looks like: above the ceiling it needs all 16 slots
*concurrently* held, so it depends on how many workers overlap, and by 20 they
always do.

## Why nobody has seen it

Every box that has ever run this suite has had **≤ 16 hardware threads** —
plexus has 12. Below the ceiling a free slot always exists, the fallthrough is
unreachable, and the code is correct. plexus's `pass` on this job is therefore a
statement about plexus's core count, not about the runtime, and it would have
stayed green forever on that hardware.

This is the value of a second watcher box stated concretely: `seven` is 24
threads, and the first suite it ran surfaced a latent memory-corruption bug that
12-core hardware structurally cannot reach.

## Scope — bigger than the one test

Any `--threadsafe` program that runs a parallel-for wider than 16 workers on a
17+ thread host hits this. The test is the messenger; `lib/rtl/scheduler.pas` is
the subject, and `asyncnet`, `httpjson`, `netconnect` and `dns_async` all build
on the same reactor table.

## Fix, in order of what is defensible

1. **Guard the exhaustion.** Mirror the `MAX_CO` arm exactly: no free slot ⇒
   named fatal, not slot 0. This alone converts silent corruption into a
   diagnosable halt and is the part that should not wait.
2. **Then raise the ceiling** — size `reactors` from the online CPU count, or
   pick a bound above any plausible host. Doing this *without* step 1 just moves
   the cliff to a wider box, which is how it stayed hidden this long.

Filing rather than fixing: `lib/rtl/**` is a file-lane this session does not
hold. Found and reduced by the Track T agent on `seven` under the provenance
rule — my box's run produced it, so the reduction is mine and the fix is the
lane's.

---

## ROUTING, 2026-08-29 — retracked **A → B**. Same priority, different lane.

`lib/rtl/scheduler.pas` is **Track B** ground: CLAUDE.md puts `lib/rtl` (Pascal)
in Track B, libraries. Track A is `compiler/**` — AST, IR, symtab, backends, ABI,
ELF. The `bug-a-` slug stays (renaming breaks the `resolve` citations that key
off it); the **frontmatter is what the ranker reads**, and it now says B.

This matters for who can take it, not for how it is fixed. B builds with
`$(PXX_STABLE)` and never rebuilds the compiler, so this needs **no pin and no
self-host gate** — `make lib-test` plus the reproduction below is the whole
verification. Filed as A it would have queued behind the shared-file lane and
waited on an A holder it does not need.

**The fix order in the ticket stands and is the important part:** guard the
exhaustion first, mirroring the `MAX_CO` arm forty lines below, *then* consider
raising the ceiling. Raising it alone relocates the cliff to a wider box, which
is precisely how this survived to be found on the first machine with more than
16 hardware threads.

## The general finding — a PASS that is a statement about the host

`plexus.json` reads **`pass`** for this job, and that green says nothing about the
runtime: **every box that has ever run this suite has had ≤16 hardware threads.**
Below `MAX_REACTORS` the fallthrough is unreachable and the code is genuinely
correct, so the job would have stayed green on that hardware forever. No amount
of reading the green harder could reach it; it took different hardware.

This is the exact **inverse of the host-red case** triaged this morning, and the
pair is worth holding together:

| | reads as | actually says |
| --- | --- | --- |
| host **RED** (the 18-job cascade) | a regression in the range | this box lacks a loader |
| host **GREEN** (this bug) | the code is correct | this box is too small to reach the bug |

The red one is noisy, gets triaged, and wastes an afternoon. **The green one is
silent and waits years.** A green job is a claim bounded by the machine that ran
it, and nothing in a report states those bounds — the instrument's scope is
invisible in its own output, one more time.

**Operational form:** when a suite has only ever run on one class of hardware,
its passes are untested in every dimension that hardware holds constant — core
count, page size, cache line, endianness, pointer width, clock granularity.
Track T's cross-host comparison is what made this cheap: *three of seven's native
reds read `pass` on plexus, which is the shape that says suspect host coupling* —
and for two of the three that was right. This was the third, and it inverted.

## Sweep: is this a pattern or an incident? — ONE instance, and the tree already holds BOTH correct answers

Asked of all of `lib/rtl` (a loop that searches for a free slot and leaves a
default in place when it finds none). The reactor table is the only accidental
instance. What makes that interesting is the other two arms, which are correct in
*different* ways:

| site | ceiling | exhaustion is | on exhaustion |
| --- | --- | --- | --- |
| `scheduler.pas:207` `CurR` (reactors) | 16 | **never detected** — `slot := 0` is the initializer | silently aliases a live thread's reactor ⇒ corruption |
| `scheduler.pas:254` `MAX_CO` (coroutines) | 64 | detected | `writeln('fatal: ... out of coroutine slots'); Halt(216)` |
| `sockets.pas:237` `ErrnoSlot` | 64 | detected — `free := -1` sentinel, `if free < 0` | shares slot 0 **on purpose**, with the reason in a comment |

`sockets.pas` is the same fallback the reactor path performs by accident, except
it is chosen, checked, and argued:

```pascal
  { More live threads than slots: slot 0 is shared rather than refused, because
    a wrong errno is recoverable and a crash in a socket wrapper is not. }
  if free < 0 then free := 0;
```

**Do not copy that answer here.** Its rationale is a claim about errno, and it
does not transfer: a wrong errno is recoverable, a shared *reactor* is coroutine
state driven by two threads at once. The transferable part is the `-1` sentinel
and the explicit test — the shape that makes exhaustion a decision instead of a
fallthrough. Between the two precedents, `MAX_CO`'s refusal is the one whose
consequence matches this table.

Also worth noting for sizing: both other tables are **64**, four times the
reactor ceiling, and neither is reachable on this box's 24 threads. `MAX_REACTORS
= 16` is the only limit in `lib/rtl` that ordinary hardware now exceeds.

## Resolved — and the "needs a 24-core box" premise is FALSE

The dispatch came with a verification boundary: *this box has 12 cores, the
defect needs 17 threads, so you can write the fix but cannot witness it.* That
boundary does not exist. **It reproduces on 12 cores, in one line.**

`MAX_REACTORS` is exhausted by the number of **worker threads**, and the worker
count is not the core count — it is `PXXParForWorkers`, which merely *defaults*
to `sched_getaffinity`. `palparallel` already exports the override:

```pascal
  PXXSetParForWorkers(20);   { PAR_MAX_WORKERS = 64 is the only ceiling }
```

With that line, the ticket's own program fails on this 12-core host:

| | runs |
| --- | --- |
| unfixed, 20 workers, 12 cores | **0 / 8 clean** — canary fatal, `err=37`, `err=50`, `err=59`, and hard crashes with no output |
| fixed, 20 workers, 12 cores | 10 / 10 clean |

The ticket's `taskset` table was a correct measurement with a wrong inference
attached. `taskset` changes the affinity mask, `QueryCpuCount` reads the
affinity mask, and the worker count follows — so the table was dialling the
**worker count** and reading it as a property of the hardware. Cores were the
proxy, never the cause, and "12-core hardware structurally cannot reach it" was
the one sentence in the ticket that nothing had measured. Everything else in it
holds exactly as written.

This matters beyond this bug: the conclusion drawn was that finding it *required*
a second, larger watcher box. It required a second box to be **noticed** —
nothing more. The reproduction was always one exported setter away, and the
general lesson is the ticket's own, turned on itself: **a green is bounded by
the machine that ran it, and so is a red.**

## The fix, in the ticket's own order

**1. Guard the exhaustion.** `slot := -1` as a sentinel, and a loud refusal when
the scan finds nothing — the shape `sockets.pas` uses, with the consequence
`MAX_CO` chose.

**2. Raise the ceiling — and this one is not optional.** `MAX_REACTORS` is now
**64**, matching `PAR_MAX_WORKERS` (the hard cap on a parallel-for's width) and
the two other tables in `lib/rtl`. With the guard alone at 16, every ordinary
`parallel for` containing async work on a 17+ thread host would have **halted**
— converting silent corruption into a guaranteed hard failure for exactly the
users on the big hardware this was found on. The guard is what makes raising it
safe; raising it is what makes the guard sane to ship. Cost is BSS: 82,012 →
195,292 bytes for a `--threadsafe` binary, zero-filled and untouched until used.

## The third defect, found while proving the second

`Halt(216)` was the obvious body for the guard, mirroring `MAX_CO`. It is wrong
here, and the way it is wrong is this repo's favourite shape. Measured with
`MAX_REACTORS` lowered to 2:

| body | 3 workers | 4 | 8 | 20 |
| --- | --- | --- | --- | --- |
| `Halt(216)` | 216 216 216 | **0 216 0** | **0 0 0** | 216 216 216 |
| `exit_group(216)` | 216 ×6 | 216 ×6 | 216 ×6 | 216 ×6 |

**With `Halt` the exit status is unreliable — it races.** Same binary, same
width, different answers between runs. So the fatal sometimes reports SUCCESS,
and a harness reading the status sees a pass.

**A correction to my own first reading of this**, which is the part worth
keeping. I first sampled each width once, got 216 / 0 / 0, and wrote down
"concurrent Halt loses the status: one refusal is fine, two or more exit 0" —
a clean deterministic rule, and I had put it in a source comment before I
re-measured. Repeating the runs destroyed it: 4 workers gives 0, 216, 0. And the
obvious minimal repro **fails to reproduce at all** — six plain `palthread`
threads each calling `Halt(216)` exited 216 in 6/6 runs, so "concurrent Halt" is
not sufficient and something about halting inside a parallel-for worker during
reactor attachment is involved. That is where it stands: **observed, reproduced,
and NOT diagnosed.**

One sample per cell reads exactly like a measurement and is a coin flip with a
table drawn around it. The named cause would have outlived me in a comment.
(Related in shape to the i386 `exit_group` number in `pxxcio.pas` — 231 is
x86-64's, so on i386 it called `fgetxattr` and every failing C program exited 0.
There too, what got lost was the report of the failure rather than the failure.)

Serialising it did not help and was worse. Holding `regLock` across the fatal
hung the process (exit 124 under `timeout`, at 4, 8 and 20 workers); releasing it
and parking the losers hung it too, for the real reason — **`Halt`'s exit path
joins the worker threads**, so a parked thread is one the join waits on forever.

So the arm calls `exit_group` directly (inline syscall numbers, the pattern this
unit already uses for `gettid` rather than depending on `palthread`). It joins
nothing, races nothing, and skips finalizers — the correct trade when the state
being escaped is two OS threads sharing one coroutine table. Result: **exit 216
with exactly one message, at 3, 4, 8, 20 and 64 workers.**

The underlying `Halt` race is not this unit's and is filed separately:
[[bug-b-concurrent-halt-from-several-threads-exits-0]].

## Tests — both reachable on any host, neither needs a big box

- `test/test_sched_reactors_wide.pas` — 20 workers via `PXXSetParForWorkers`,
  expects `SCHED WIDE OK`. This is the user-facing regression. **0/8 pre-fix on
  12 cores**, 10/10 after.
- `test/test_sched_reactor_exhaustion.pas` — built `-dPXX_SCHED_TINY_REACTORS`,
  which lowers `MAX_REACTORS` to 2 so three threads overrun it deterministically.
  Asserts the named fatal **and exit 216**, because "prints a fatal" and "fails"
  are different claims and only the status is what a harness reads. Pre-fix it
  prints `UNREACHED` and exits 0.

The define exists because raising the ceiling to 64 makes the guard **unreachable
from Pascal** — no `parallel for` can exceed `PAR_MAX_WORKERS`. An unreachable
guard is an untested one, and this ticket is about what untested code does.

Both wired into `test-threads` beside `test_async_parallel_compat`, and verified
by extracting the recipe and running it through **make's own expansion** — my
first attempt hand-substituted `$$` and produced a false mismatch, which is the
same "a hand-copied oracle is a second implementation" trap as retyping an
expected string.

Gate: `make lib-test` (Track B), no pin and no self-host needed, per the routing
note above.

## Deliberately NOT changed: the `MAX_CO` arm

`SpawnSized`'s `MAX_CO` guard still uses `Halt(216)` and therefore carries the
same latent exposure — measured at two concurrently-refused threads it exited
216 correctly, so it is not *observed* broken, but nothing about it is
structurally safer than the arm this ticket rewrote. Left alone on purpose: it
is outside this ticket, it is not currently failing, and swapping a working
fatal for a different mechanism is how a fix trades one bug for two. Recorded in
[[bug-b-concurrent-halt-from-several-threads-exits-0]] as the place to look
next, with the reproduction that would settle it.

## Log
- 2026-08-29 — resolved, commit 9bd3da8b2.
