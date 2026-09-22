---
slug: umbrella-lekkerzeilen-runs-at-15-fps
track: E
prio: 95
type: umbrella
status: backlog
owner: ""
created: 2026-09-22
found-by: owner (directive, 2026-09-22), evidence assembled by frankuser, ranked by frankz-e5
tags: [perf, lekkerzeilen, nilpy, frame-rate, amdahl]
blocked-by:
  - perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program
  - perf-a-every-return-releases-every-managed-local-even-the-untouched-ones
  - perf-b-the-inverse-trig-functions-have-no-fast-arm-and-cost-16-microseconds
  - perf-n-an-imported-npy-module-costs-13x-per-function-versus-the-same-code-inline
  - perf-o-the-variant-hidden-dest-clear-is-a-proc-call-where-the-store-arm-uses-an-inline-blob
summary: "OWNER DIRECTIVE 2026-09-22: `all performance issues have the highest prio right now. file appropiate tickets and lets start working on them. hopefully, by the end of the day we have 15+ fps`. This umbrella exists so the perf tickets inherit that rank through edges rather than by hand-editing prios. READ THE ARITHMETIC BEFORE PICKING ANYTHING: the frame is 391 ms of work and 15 fps needs 67 ms, so the target is ~18x, and the profile is FLAT -- no row exceeds 16.5% and the largest four sum to 43.5%, which if deleted ENTIRELY gives 391 -> 221 ms = 4.5 fps. A sum of 10% wins cannot reach 15 fps; only something structural can. Ranked first is therefore NOT the biggest measured row but `perf-n-one-computed-getattr...`, because it is the only candidate whose upside is UNMEASURED rather than already bounded below the target, and because boxing sits UPSTREAM of refcount, allocator and variant-dispatch (three rows totalling 37%) rather than beside them. Its first action is a MEASUREMENT, not a fix, and the controlled harness already exists. THREE CAVEATS THAT MUST NOT BE RE-DISCOVERED, each from the measuring seat's own hand: the 16.5% heap-lock row OVERSTATES itself (standalone 400k-object A/B, interleaved, 12 rounds: +4.9% with overlapping distributions -- sampling skid on a serialising `lock xchg`, so nobody may rank on 16.5% as headroom); the 13% software-numerics row SPLITS and half is already fixed (every bignum sample was the audio xorshift, `8cbec7eab`, in pin v416 -- the survivor is double-double inverse trig at ~106 bits where a scene needs ~24, and it GROWS as a share under `--silent`); and refcount is CALL overhead not atomic overhead (3.772 ns/slot = 79% call/ret pair, and an inline nil-test takes it to 1.667, a 56% runtime saving with NO liveness analysis). DO NOT REVERT the computed-getattr widening -- it is what stops a SIGSEGV in imported modules. This RE-RANKS the release and ESP32 window recorded in demo-timebox-close-2026-09-21.md; it does not replace it."
---

# Umbrella: lekkerzeilen runs at 15 fps

**Owner directive, 2026-09-22, verbatim:**

> *"all performance issues have the highest prio right now. file appropiate
> tickets and lets start working on them. hopefully, by the end of the day we
> have 15+ fps"*

**This is a RE-RANK, not a replacement.** `devdocs/dev/demo-timebox-close-2026-09-21.md`
says the window from 2026-09-22 is the release and stabilising ESP32. The owner
re-opened performance explicitly and did not close those; read this umbrella as
moving perf to the front of the same queue.

## The arithmetic, and it is the first thing to read

    frame today        391 ms of work
    15 fps needs        67 ms
    required            ~18x

    the four largest rows, deleted ENTIRELY:
      heap lock 16.5 + refcount 14.0 + software numerics 13.0 + allocator 11.5  =  43.5%
      391 ms -> 221 ms -> 4.5 fps

**The profile is flat. There is no 90% block.** Amdahl therefore says a sum of
10% wins cannot reach the target, however many of them land. **15 fps is not
reachable today by the levers on this list**, and that is stated here rather
than discovered at 23:00. What IS reachable is a real multiple, and the way to
get one is a structural change rather than a stack of slices.

## The authoritative profile

`lekkerzeilen@devdocs/perf/PROFILE-2026-09-21.md`. **Most seats do not know it
exists and it is a FULL SCENE, not a synthetic loop.**

**Population, because a row without one is unquotable:** `--region rijn`,
interactive, settled 25 s, **200 main-thread leaf samples**, gdb SIGINT
jittered, v414 binary (byte-identical under v415, verified by hash), wayland
pinned. **n=200, so every row is ±3-5 points.**

    16.5  heap lock            11.5  variant arith + dispatch     5.0  demo source proper
    14.0  refcount / ARC       11.5  allocator                    4.5  frame pacing (not work)
    13.0  software numerics     8.5  long tail (17 syms, 1 each)  7.5  library (libc 14, GL 1)

## Why the ranking is not the profile order

**The largest row is not the first ticket, and the reason is not a preference.**
Each of the big rows has a measured or bounded upside that is already too small,
and the one unbounded candidate is ranked first **because its upside is
unmeasured, not because it is known to be large.** Its first action is the
measurement.

1. **`perf-n-one-computed-getattr-...`** — structural, upside **unmeasured**.
   `PyModuleHasComputedGetattr` is all-or-nothing: one computed `getattr`
   anywhere in the import closure makes `PyMethodUsedAsValue` true for EVERY
   name, so every method in the program takes the function-object ABI and pays
   boxing. lekkerzeilen has exactly one — `lekkerzeilen/gfx.py:349`,
   `handle = getattr(self, attr)`. **Boxing sits upstream of refcount,
   allocator and variant-dispatch — 37% between them — rather than beside
   them.** Controlled measurement exists for **SIZE only** (`5b1045dad`:
   +112,025 B, +0.93%, `procs` IDENTICAL, so the growth is boxing inside
   existing bodies). **The run-time cost is stated in the ticket as unmeasured,
   and measuring it is the first action, not fixing it.** The controlled A/B
   harness already exists and `franks-5b` owns it.
   **DO NOT REVERT THE WIDENING.** `0c508e507` is what stops a SIGSEGV
   (rc=139, two fixtures) from a computed getattr in an imported module. The
   open question is whether the coarse arm can be NARROWED without reopening
   that, and the ticket's own honest answer is that it probably cannot be
   narrowed by name — a computed getattr is exactly the case where no token
   spells the name.

2. **`perf-a-every-return-releases-...`** — p70, already in `working/`,
   **re-rank it, do not re-file it.** The SIZE half has landed on six backends
   (−33% .text). The **runtime half is UNSTARTED and unstaffed, not blocked.**
   The decomposition is the useful part: 3.772 ns/slot = prologue store 0.526 +
   epilogue load 0.262 + **call/ret pair 2.984 (79%)**, body 0.879 inlined. **An
   inline nil-test at the call site takes 3.772 → 1.667 — a 56% runtime saving
   with NO liveness analysis.** That is the cheapest large win on the board.

3. **`perf-b-the-inverse-trig-...`** — the surviving half of the software-numerics
   row. Double-double inverse trig at ~106 bits in `lib/rtl/math.pas` where a
   scene needs ~24. It survives `--silent` and **grows as a share** (Dd\* 8 → 17
   samples). Banked at `2efde35a3` as explicitly not-to-build; **the owner has
   reversed that.** `franks-5b` has been fed this directly.

## Caveats, each flagged by the seat that measured the row

- **The 16.5% heap-lock row overstates itself.** Standalone 400k-object A/B,
  both ways, interleaved, 12 rounds, min-of-N: `--threadsafe` **509.9 vs 486.2
  ns/object, +4.9%, distributions overlapping.** Sampling skid on a serialising
  `lock xchg`. **Nobody may rank a ticket on 16.5% as available headroom.**
- **The 13% software-numerics row splits and half is already fixed.** Every
  bignum sample (`BMulSmall` 7, `BNorm` 4, `BDivMod` 1, `BIsZero` 1 = 13) was
  the audio engine's xorshift; `--silent` had zero `B*` symbols. That is
  `8cbec7eab`, **in pin v416.**
- **Refcount is CALL overhead, not atomic overhead.** `274a9da6c` took
  retain/release out from under the heap lock; an update is one `lock inc`/`lock
  dec` at `[rax-16]`. Do not file an atomics ticket.

## Seats already fed directly — do not double-dispatch

`franks-5b` (double-double, and it owns the controlled-A/B harness);
`lekkerzeilen-7a` (v416 roofs baseline).

**`frankb-8e` IS AVAILABLE. This section said it was mid-ticket and that was
already false when this file was committed** — a79934842, eabcf8e09 and
b09fd02c3 landed 09:06–09:19 and the umbrella was committed 09:37. The ruling
that produced the wrong line was correct (*a directive re-ranks the QUEUE, not
work in flight*) and it was applied to a report of the seat's state rather than
to the tree, eighteen minutes after the tree disagreed. **Corrected by frankh-c0,
which had mutated the fix in its own checkout to confirm it.** Kept rather than
deleted because the shape recurs: a coordinator's note about *who is busy* is the
fastest-decaying sentence in any ticket, and nothing announces when it turns.

**And 8e is the right seat for item 2 rather than merely a free one** (c0's
point, from 8e's own night): it spent the night on DCE reachability and the wasm
export surface — what gets emitted and what gets called. **The p70 is a call-site
emission question, not an allocator question.** One subsystem over.

`frankh-c0` is mid-tier on the `--dce` → `-O2` promotion proof (size, not perf)
and takes perf after it lands.

## What would retire this umbrella

A measured frame time at or under 67 ms on a shipped scene, with the region,
sample count and pin version stated beside it. **A sum of percentage claims does
not retire it**; the arithmetic above is why.

**HOW TO REPORT PARTIAL PROGRESS, AND IT IS NOT AS A FRACTION** (frankh-c0,
2026-09-22). An 18x target makes every accumulated win **un-bankable until the
structural one lands**, so a win against this umbrella is not progress *toward*
it. **The honest intermediate report at 18:00 with 8 fps in hand is "no", not
"40%"** — and the fraction is the tempting form precisely because it is
arithmetically defensible and reads as momentum. Report a measured speedup as
its own result, against its own baseline, and report this umbrella's status
separately as met or not met. A seat that reports 40% has told the owner
something true and left him expecting 15 fps.
