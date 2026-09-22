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
summary: "summary: "OWNER DIRECTIVE 2026-09-22: `all performance issues have the highest prio right now. file appropiate tickets and lets start working on them. hopefully, by the end of the day we have 15+ fps`. This umbrella exists so the perf tickets inherit that rank through edges rather than by hand-editing prios. THE NUMBER IS 8.0x, MEASURED ON THE SCENE THAT SHIPS, AND IT IS A PROPERTY OF THAT SCENE -- never quote a bare factor. 7a, `lekkerzeilen@devdocs/perf/ROOFS-2026-09-22.md` (`62859ff`), `world/roofs`, windowed, vsync ON, audio ON, quiet box: pxx median 1.887 fps = 530 ms/frame over 19 windows; 15 fps is 66.7 ms; 8.0x. THE GAP IS 19.7x AGAINST A WORKING ORACLE: CPython 3.14.4 runs the SAME scene at median 37.140 fps (27 ms) over 414 windows, same box, same session. So 15 fps is NOT a physics question -- it is a compiler gap, and that is the frame to carry. THIS TICKET HAS CARRIED FOUR FACTORS IN ONE DAY (18x, 5.9x, 9.4x, now 8.0x) AND EVERY ONE WAS ARITHMETICALLY CORRECT ON A DIFFERENT FRAME; the 391 ms was a v413 vsync-off `--region rijn` row, and the 624 ms pair it replaced was taken while the box was at load 27-30. TREAT ANY TWO TIMINGS TAKEN AT DIFFERENT TIMES ON THIS BOX AS 20% APART FOR FREE, and do not report a ratio change smaller than that as a finding -- load is NOT in the stamp. AND DO NOT RANK BY `per-call cost x calls per frame`: 7a predicted 12% from a 12.3x per-call win and measured 3.3% (P(B faster)=0.653, z=1.57, its own within-arm noise 8.8%), because `Soundscape.update` tops the audio queue to a fixed BYTE target, so work per frame is capped and does not grow as the frame slows. A call count must be a SEPARATELY MEASURED quantity, never one derived from frame duration. WHAT NOBODY HAS: a decomposition of a roofs frame -- ~470 ms of 530 is unaccounted for once vsync is removed, every lever below was identified on `--region rijn`, and the 43.5% flat-profile figure is an answer about a scene nobody runs. That decomposition outranks every edge here and 7a has it next. NOT THE CAUSE, measured: vsync, audio (ON throughout), the RNG (~6 ms), and inverse trig (SETTLED, 0.22% -- do not rank it). Refcount is CALL overhead not atomic overhead (3.772 ns/slot = 79% call/ret; an inline nil-test takes it to 1.667 with NO liveness analysis). The 16.5% heap-lock row OVERSTATES itself (+4.9%, overlapping distributions). DO NOT REVERT the computed-getattr widening -- it stops a SIGSEGV in imported modules. This RE-RANKS the release and ESP32 window in demo-timebox-close-2026-09-21.md; it does not replace it."
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

## The arithmetic, on the scene that actually ships

**7a, `lekkerzeilen@devdocs/perf/ROOFS-2026-09-22.md`, commit `62859ff`** —
`world/roofs`, windowed, **vsync ON, audio ON**, default boat, no interaction,
**quiet box**. Each window is one interval between `FPSMARK` lines, 20 frames
apart.

    arm  what                       windows   min      median        max      frame
    A    pxx, `<<`/`>>` spelling         17   1.355    1.826 fps     1.991    548 ms
    B    pxx, `*`/`//` spelling          19   1.734    1.887 fps     1.925    530 ms
    C    CPython 3.14.4                 414  14.524   37.140 fps    49.628     27 ms

    15 fps needs 66.7 ms      ->  pxx is 8.0x away
    ratio at the medians      ->  19.7x, pxx against CPython

    region=roofs tiles=4 worldindex=5cb61f3753c90cb6 twins=uv
    compiler=fddc21e7e6615f80 promocore=fa1e57a9b1e5564c source=5c34d02
    armA=c91f50b560d56230 armB=7a24e6c56255e93e session=90c77059f105dacb

**THE ORACLE IS THE POINT, NOT THE FACTOR.** CPython runs **this** scene, on
this box, in the same session, at 37.1 fps. **15 fps is therefore not a physics
question and this umbrella is not a fatalistic document.** It is a **19.7x
compiler gap against a working oracle running the same program.** Anyone who
reads this ticket as "the target is unreachable" has read the wrong half.

## Four factors in one day, every one arithmetically correct

**Recorded because the next seat will otherwise quote a bare factor**, and
because the pattern is the finding: **the arithmetic was never the error.**

| said | frame it was computed on | why it was wrong |
| --- | --- | --- |
| **18x** | 391 ms, v413, **vsync OFF**, `--region rijn` | different scene, different pin |
| **5.9x** | an open-water frame where the vsync wait dominated | different scene |
| **9.4x** | 624 ms, v416, `world/roofs` | **right scene, loaded box** |
| **8.0x** | **530 ms, `world/roofs`, quiet box** | current |

**A reachability factor is a property of the scene AND the machine state it was
measured on.** The 9.4x row is the instructive one: **right scene, right pin,
correct arithmetic, and still 18% out** — and it was the row nobody had marked
as doubtful, because the pxx side had a full stamp.

## A complete stamp is what made me stop looking

**The 9.4x row is instructive precisely because it had no defect anyone could
point at.** Right scene, right pin, correct arithmetic, eleven recorded axes all
matching — and 18% out. I marked the CPython side unbacked because its file had
been deleted, and left the pxx side alone **because it carried a full stamp.**
That is the whole failure: **a complete population line reads as a checked one.**

## TREAT A SINGLE TIMING ON THIS BOX AS ~20% SOFT — AND A RATIO AS UNBOUNDED

The 624 ms/22.4 fps pair was taken while the box sat at **load 27–30** with
other sessions compiling; this pair ran quiet because `franks-5b` held off the
CPU. Same binaries, same scene, same pin. **CPython got 66% faster and pxx only
18%** — consistent with CPython being CPU-bound at 27 ms while pxx at 530 ms is
bound by something that contends less, which would also explain the ratio moving
14.0 → 19.7. **Hypothesis only: load was not recorded, so it cannot be checked.**

**THE 20% IS A PLACEHOLDER, NOT A CONSTANT** — it comes from one observed jump
between two moments with load recorded at neither end. It has the shape of a
haircut, not a measurement. Do not let it harden.

**AND IT DOES NOT APPLY TO RATIOS, WHICH IS WHAT THIS UMBRELLA RANKS BY.** The
two arms did not move together:

    CPython  22.4 -> 37.1 fps   +66%
    pxx       1.603 -> 1.887    +18%
    ratio     14.0 -> 19.7      +41%

**A reader who applies "20% for free" to a ratio concludes 14.0 and 19.7 are
compatible. They are not** — the ratio moved twice the per-arm haircut, because
**contention is DIFFERENTIAL**: a CPU-bound arm at 27 ms contends and a 530 ms
arm bound by something else does not.

**So the warning is two sentences, and the second is the one that would have
caught this:**

1. Treat a single timing as **~20% soft**.
2. Treat a **RATIO of two arms with different load sensitivity as UNBOUNDED**
   until both are measured **in one interleaved session on a quiet box.**

Same animal as the rule that a ratio divides out a shared factor but never an
**additive or asymmetric** term — arriving here from the load side rather than
the vsync side.

## DO NOT RANK BY "per-call cost x calls per frame"

**7a predicted 12% from a 12.3x per-call win and measured 3.3%** — within-arm
run-to-run noise is 8.8%, Mann-Whitney over 17x19 windows gives
**P(B faster) = 0.653, z = 1.57. Its own A/B does not resolve.** Wrong by four
times, **in the direction that flattered its own change.**

**The mechanism: `Soundscape.update` tops the audio queue to a fixed BYTE
target, not to a frame's worth of audio**, so work per frame is **capped** and
does not grow as the frame slows. (Unmeasured — no audio diagnostics in the run
files — and labelled a hypothesis in 7a's own doc.)

**So a call count must be a SEPARATELY MEASURED quantity, never one derived from
frame duration.** Any lever on this list ranked that way inherits the same hole.

## What nobody has, and it probably outranks every edge below

**~470 ms OF A 530 ms FRAME IS UNACCOUNTED FOR once vsync is removed, and
NOBODY HAS DECOMPOSED A ROOFS FRAME.** Every lever in this umbrella was
identified on a profile of **`--region rijn`** — a different scene, two pins
ago, vsync off. **So the flat-profile picture below is a property of a scene
nobody runs, and it may not describe the shipping frame at all.** The 43.5%
figure in particular is an answer about `rijn`.

**Decomposing a roofs frame is therefore the honest first action**, and it is
the only way to learn which levers the shipping scene actually has. `7a` has
proposed it, in its own lane and on its own display. **Nothing here dispatches
it and nobody may treat this paragraph as a grant.**

**Also NOT the cause, all three measured rather than assumed:** vsync (above),
**audio** (ON in every row of the baseline), and **the RNG** (~6 ms of 624 at
v416). Those are the three things today was spent near, and the gap is none of
them.

## The old profile — `rijn`, and read it as history now

`lekkerzeilen@devdocs/perf/PROFILE-2026-09-21.md`. **It is a full scene, not a
synthetic loop, and it is the wrong scene.**

**Population, because a row without one is unquotable:** `--region rijn`,
interactive, settled 25 s, **200 main-thread leaf samples**, gdb SIGINT
jittered, v414 binary (byte-identical under v415, verified by hash), wayland
pinned. **n=200, so every row is ±3-5 points.**

    16.5  heap lock            11.5  variant arith + dispatch     5.0  demo source proper
    14.0  refcount / ARC       11.5  allocator                    4.5  frame pacing (not work)
    13.0  software numerics     8.5  long tail (17 syms, 1 each)  7.5  library (libc 14, GL 1)

**AND THE WORD `rijn` IN THAT POPULATION LINE IS ITSELF SUSPECT.**
`world/roofs` and `world/rijn` **both record `meta.name='rijn'`** in their
`index.lzi`, and the directory never appears in any output — **verified here by
query, not relayed**: `roofs` answers `meta.name=rijn` with **4** tiles, `rijn`
answers `meta.name=rijn` with **432**. So a banner reading "rijn" proves
nothing about which scene ran. **TILE COUNT IS NOT A
DISCRIMINATOR AND THIS PARAGRAPH SAID IT WAS FOR AN HOUR** — `roofs` and `uv`
agree on name, tiles, pounds and routes, and the 4-tile class is the one the
shipping scene is in. Enumerated: twelve worlds, three names, two identical
classes. See `bug-e-every-world-reports-meta-name-rijn-...` (p60).

**THIS PROFILE'S OWN LABEL IS NOT AFFECTED, and 7a checked rather than
inferred:** `PROFILE-2026-09-21.md:29` records `--region rijn` as an
**invocation**, not a banner reading, and `:222` puts `atan2` at **46.0
calls/frame on roofs against 1,258.4 on rijn**. No 4-tile run produces that.
**The doubt applies to anything citing a banner; this is not one.**

## Why the ranking is not the profile order

**All five edges were ranked on the `rijn` profile and none has been checked
against a roofs frame.** That does not make them wrong — they are real defects
with measured costs — but it means **the ORDER below is provisional and a roofs
decomposition may reorder it entirely.** Take one, by all means; do not defend
its position on the strength of a percentage measured elsewhere.

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
   `handle = getattr(self, attr)`.
   **THE SOURCE-SIDE UNROLL IS DEAD AS OF 2026-09-22 AND THIS ITEM DROPS BELOW
   ITEM 2.** The plan was to remove that one call and flip the flag. **`5b` ran
   `PXXDBG=a.srcmap:*` against the pin and all four ladder rungs came back
   PLANTED — including the two it had predicted absent — so `_sdl2.py:212`
   holds `PyModuleHasComputedGetattr` true whatever happens to `gfx.py`.**
   Killed for one compile and no display time; `lekkerzeilen@83bb324` — **that
   sha is in the lekkerzeilen repo, not this one.** 7a's pre-registered
   prediction is **unspent, not resolved** (antecedent false) and **must not be
   scored either way.**
   **WHAT SURVIVES IS THE COMPILER-SIDE NARROWING, AND IT HAS NO KNOWN
   MECHANISM** — the ticket's own honest answer is that the coarse arm probably
   cannot be narrowed by name, because a computed getattr is exactly the case
   where no token spells the name. **What died is the cheap way to MEASURE the
   lever, not an estimate of its size**, and that is what moves it below item 2.
   **Boxing sits upstream of refcount,
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

3. **`perf-b-the-inverse-trig-...`** — **SETTLED 2026-09-22 AND IT IS NOT A
   FRAME-RATE LEVER. Do not rank it here.** Double-double inverse trig at ~106
   bits in `lib/rtl/math.pas` where a scene needs ~24, and it does grow as a
   share under `--silent` (Dd\* 8 → 17 samples) **on `rijn`**. The share
   question did not need the roofs decomposition — it needed the call count, and
   7a had it: **`atan2` runs 1,258.4/frame on `rijn` and 46.0/frame on `roofs`,
   a 27x collapse** (`PROFILE-2026-09-21.md:222`). Against today's 624 ms frame:
   **46 × 29,463 ns = 1.36 ms, 0.22%.**
   **`franks-5b` landed `6b8b45af4` with "THIS IS NOT A FRAME-RATE LEVER" in the
   commit body and the ticket summary**, and re-ranked it as a
   **correctness-of-effort** fix — ~106 bits for a 53-bit answer, `ArcCos` at
   1095x `Sqrt` against libm's 20–50 ns. It also moved its own number the
   unflattering way: 0.13% → 0.22%, because re-measuring the dd arm gave 29.5 µs
   against the 14.4 µs its ticket published. **Both rows are carried
   unreconciled.**
   **POPULATION LIMIT, raised by 5b against its own row before anyone asked: the
   call counts are CPython's**, on the argument that the program logic is
   identical. That is an argument, not a pxx measurement — but a 27x collapse
   does not invert into a lever, so it does not reopen the ranking.

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

A measured frame time at or under **66.7 ms on `world/roofs`**, windowed, vsync
ON, audio ON, **on a quiet box** — the same configuration as arm B above — with
the full stamp beside it (`region`, `tiles`, `worldindex`, `twins`, compiler,
promocore, source, session) and the window count. **Not `rijn`, and not a
`rijn`-labelled run whose label came from a banner.** **And not a single run:**
within-arm run-to-run noise here is 8.8% and machine load moves a timing 20%,
so a retirement claim wants windows and a median, not a best frame — **and both
arms measured in ONE INTERLEAVED SESSION.** Two arms taken on the same quiet box
hours apart is the failure recorded above, not a fix for it. **A sum of percentage
claims does not retire it**; the table above is why.

**HOW TO REPORT PARTIAL PROGRESS, AND IT IS NOT AS A FRACTION** (frankh-c0,
2026-09-22). An 18x target makes every accumulated win **un-bankable until the
structural one lands**, so a win against this umbrella is not progress *toward*
it. **The honest intermediate report at 18:00 with 8 fps in hand is "no", not
"40%"** — and the fraction is the tempting form precisely because it is
arithmetically defensible and reads as momentum. Report a measured speedup as
its own result, against its own baseline, and report this umbrella's status
separately as met or not met. A seat that reports 40% has told the owner
something true and left him expecting 15 fps.
