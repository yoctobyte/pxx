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
summary: "OWNER DIRECTIVE 2026-09-22: `all performance issues have the highest prio right now. file appropiate tickets and lets start working on them. hopefully, by the end of the day we have 15+ fps`. This umbrella exists so the perf tickets inherit that rank through edges rather than by hand-editing prios. THE NUMBER IS 9.4x AND IT IS A PROPERTY OF A NAMED SCENE, NEVER A BARE FACTOR -- 7a's stamped baseline, pin v416, world/roofs, windowed, vsync ON, audio ON, no interaction: pxx median 1.603 fps = 624 ms/frame over 11 windows; 15 fps is 66.7 ms; 9.4x. EARLIER VERSIONS OF THIS SECTION SAID 18x AND 5.9x AND BOTH WERE COMPUTED ON A FRAME NOBODY SHIPS (a v413 vsync-off `--region rijn` row at 391 ms); each was arithmetically correct and each was taken on the wrong scene, so carry the factor WITH its scene and pin or not at all. THE ORACLE CLAIM IS **UNBACKED AS OF 2026-09-22 -- ARTEFACT DESTROYED, RE-RUN IN FLIGHT** and must not be quoted until it is re-confirmed: CPython at median 22.40 fps on the shipping scene, and the 14.0x ratio derived from it, survive only as 7a's recollection of a reduction it read at the time (55 windows, min 10.428 / median 22.396 / max 38.462) because the run file was deleted by its own harness. 7a's ruling, unsoftened: a number without a population, and being the measurer's own recollection does not improve it. IF IT RE-CONFIRMS, the frame to carry is that 15 fps is NOT a physics question but a ~14x compiler gap against a working oracle. THE 9.4x IS NOT AFFECTED AND NEEDS NO CPYTHON NUMBER -- it is 624 ms against a 66.7 ms target, off `diag-B.txt`, which is still on disk with its full stamp. WHAT NOBODY HAS: a decomposition of a roofs frame. Every lever below was identified on a profile of `--region rijn`, so the flat-profile picture (no row over 16.5%, largest four sum 43.5%) is a property of a scene nobody runs and MAY NOT DESCRIBE THE SHIPPING FRAME AT ALL. Decomposing a roofs frame therefore likely outranks every edge on this ticket and is the honest first action. NOT THE CAUSE, MEASURED: vsync (a tenth of a 624 ms frame -- remove it entirely and 8.5x remains), audio (ON in every row above), and the RNG (~6 ms of 624 at v416). THREE CAVEATS ON THE OLD PROFILE'S ROWS, each from the measuring seat's own hand: the 16.5% heap-lock row OVERSTATES itself (+4.9% with overlapping distributions on a controlled A/B -- nobody may rank on 16.5% as headroom); the 13% software-numerics row SPLITS and half is already fixed (`8cbec7eab`, in v416); refcount is CALL overhead not atomic overhead (3.772 ns/slot = 79% call/ret, and an inline nil-test takes it to 1.667 with NO liveness analysis). DO NOT REVERT the computed-getattr widening -- it is what stops a SIGSEGV in imported modules. This RE-RANKS the release and ESP32 window recorded in demo-timebox-close-2026-09-21.md; it does not replace it."
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

**7a's stamped roofs baseline at v416.** Windowed, **vsync ON, audio ON**,
default boat, no interaction:

    pxx        11 windows   min 1.498   median 1.603   max 1.714 fps   median frame 624 ms
    CPython    55 windows   min 10.43   median 22.40   max 38.46 fps   median frame  45 ms

    15 fps needs 66.7 ms      ->  pxx is 9.4x away
    ratio at the medians      ->  14.0x, pxx against CPython

    pin v416 fddc21e7e6615f80, promocore fa1e57a9b1e5564c, source 5c34d02,
    arms A c91f50b560d56230 / B 7a24e6c56255e93e, scene world/roofs (4 tiles),
    session 90c77059f105dacb, SDL_VIDEODRIVER=wayland

### UNBACKED AS OF 2026-09-22 — artefact destroyed, re-run in flight

**The CPython row above, and the 14.0x with it, must not be quoted until the
re-run lands.** 7a's harness step opened with `rm -f "$R"/run-*.txt` to clear
what it was about to rewrite, and that glob was wider than the set the step
owned: `run-C1.txt`, the CPython baseline measured an hour earlier, matched it.
**What survives is the reduction 7a read at the time** — 55 windows, min 10.428,
median 22.396, max 38.462 fps. **What is gone is the file, and with it the
stamp, the scene banner and the session sha.** 7a's own ruling, recorded
unsoftened at its request: *a number without a population, and the fact that it
is my recollection rather than someone else's does not improve it.*

**THE 9.4x IS NOT AFFECTED.** It is 624 ms against a 66.7 ms target and needs no
CPython number at all; the pxx side comes from `diag-B.txt`, which did not match
the glob and is still on disk with its full stamp.

**IF THE RE-RUN CONFIRMS** — it is scheduled at 150 s rather than the original
60 s, so it will be better evidence than what was lost — then the frame to carry
is the one below, and nothing in this section changes.

**THE ORACLE WOULD BE THE POINT, NOT THE FACTOR.** CPython running **this**
scene, on this box, in the same session, at ~22 fps would mean **15 fps is not a
physics question and this umbrella is not a fatalistic document** — a **~14x
compiler gap against a working oracle running the same program.** Anyone who
reads this ticket as "the target is unreachable" has read the wrong half.

**And the destructive-step lesson is 7a's and is not "scope your globs":** a
step may clear **what it is about to rewrite and nothing else.** 7a had a note
to itself, written three days earlier, about taking a baseline before something
overwrites it — and did not apply it to a destructive line in its own tool.

## The factor has moved three times today and every version was correct

Recorded because it is the reason the number above is written with its scene and
pin attached, and because the next seat will otherwise quote a bare factor.

| said | frame it was computed on | status |
| --- | --- | --- |
| **18x** | 391 ms, v413, **vsync OFF**, `--region rijn` | correct arithmetic, scene nobody ships |
| **5.9x** | an open-water frame where the vsync wait was most of it | correct arithmetic, scene nobody ships |
| **9.4x** | **624 ms, v416, vsync ON, `world/roofs`** | the first frame that belongs in the calculation |

**All three were arithmetically correct. The error was never the arithmetic.**
**A reachability factor is a property of the scene it was measured on**, so it
does not survive being quoted without one. Do not carry the 18x/5.9x pair
forward at all.

**And vsync is no longer the story.** On a 66 ms open-water frame the 52–68 ms
wait was most of the frame; on a 624 ms frame it is a tenth. **Remove it
entirely and ~564 ms of work remains — still 8.5x.**

## What nobody has, and it probably outranks every edge below

**NOBODY HAS DECOMPOSED A ROOFS FRAME.** Every lever in this umbrella was
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
ON, audio ON — **the same configuration as the baseline above** — with the
scene, tile count, window count and pin stated beside it. **Not `rijn`, and not
a `rijn`-labelled run whose label came from a banner.** **A sum of percentage
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
