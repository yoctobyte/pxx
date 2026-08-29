---
track: B
prio: 75
type: bug
blocked-by: []
summary: "lib/rtl/scheduler.pas CurR() falls back to slot 0 when all MAX_REACTORS=16 reactors are in use — `slot := 0` is the initializer and nothing checks for exhaustion. The 17th OS thread silently adopts a live thread's reactor, the two share coroutine state, and the result is memory corruption reported as 'coroutine stack overflow (canary clobbered)'. Invisible on every 12-core box; deterministic above 19 threads. Found on seven (24 cores) 2026-08-29."
status: open
owner: unassigned
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
