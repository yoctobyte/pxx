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
  - task-e-decompose-a-lekkerzeilen-roofs-frame-so-two-perf-tickets-stop-guessing-at-their-own-prize
  - perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program
  - perf-a-every-return-releases-every-managed-local-even-the-untouched-ones
  - perf-o-the-variant-hidden-dest-clear-is-a-proc-call-where-the-store-arm-uses-an-inline-blob
summary: "**15 FPS IS RETIRED AS A TARGET -- OWNER, 2026-09-22, HIS OWN WORDS: `15fps is not written in stone, just a wishful figure`.** NOTHING MAY BE RANKED BY DISTANCE TO IT, and any ticket justified as `gets us to 15` needs re-justifying on something else. The slug keeps the number so citations resolve; the GOAL is now: find the main performance issues. HIS SEQUENCE IS FINISH-THEN-MEASURE, NOT MEASURE-THEN-PICK: `i think when all current known issues are done, just profile it again`. So do NOT grow new perf tickets off the 2026-09-21 `--region rijn` profile -- that scene has now produced THREE levers measuring to approximately zero on the scene that ships, and the re-profile must be on ROOFS. WHERE WE ACTUALLY ARE, and these rows stand on their own without any target: pxx median 1.887 fps = 530 ms/frame over 19 windows on `world/roofs`, vsync ON, audio ON, quiet box; CPython 3.14.4 on the SAME scene, box and session, median 37.140 fps (27 ms) over 414 windows. THAT 19.7x AGAINST A WORKING ORACLE IS THE REAL FINDING and it needs no wishful number: the gap is OURS and it is structural. `lekkerzeilen@devdocs/perf/ROOFS-2026-09-22.md`, `62859ff`. MEASUREMENT RULES THIS TICKET HAS PAID FOR, all still binding: a factor is a property of the SCENE and the MACHINE STATE it was measured on (four factors in one day, every one arithmetically correct on a different frame); treat a single timing as ~20% soft and a RATIO of two arms with different load sensitivity as UNBOUNDED until both run interleaved on a quiet box; and NEVER rank by `per-call cost x calls per frame` -- 7a predicted 12% from a 12.3x per-call win and measured 3.3% inside its own 8.8% noise, because `Soundscape.update` caps the audio queue at a fixed BYTE target so work per frame does not grow as the frame slows. MEASURED AS NOT THE CAUSE: vsync, audio, the RNG (8.16x per shift, in-situ value nil), inverse trig (0.22%), and heap contention (the render loop is ONE thread; the 16.5% rijn heap-lock row is UNCONTENDED and a 400k-object A/B bought +4.9% with overlapping error bars). STILL LIVE: the computed-getattr flag has a shippable off switch (`fn = lib[name]`, zero computed sites) worth 112,180 bytes STATIC with its runtime value UNMEASURED; and the managed-local release sweep, whose inline nil-test landed at 56.8% off the per-slot cost against a 55.8% prediction, x86-64 and SXR_STR only. DO NOT REVERT the computed-getattr widening -- it stops a SIGSEGV in imported modules."
---

# Umbrella: lekkerzeilen performance

**THE TARGET IN THIS TICKET'S SLUG IS RETIRED. Owner, 2026-09-22, second
directive of the day, verbatim:**

> *"the goals are clear - find the main performance issues. 15fps is not written
> in stone, just a wishful figure. i think when all current known issues are
> done, just profile it again."*

**So: nothing is ranked by distance to 15 fps, and any ticket justified as
`gets us to 15` needs re-justifying on something else.** The slug keeps the
number only so existing citations resolve.

**And the SEQUENCE is his, not a preference: finish-then-measure.** Current known
perf issues land, *then* a fresh profile decides what is next. **Do not grow new
perf tickets off the 2026-09-21 `rijn` profile this afternoon** — that scene has
now produced three levers measuring to about zero on the scene that ships. **The
re-profile must be on ROOFS**; 7a has been briefed.

### PAUSED BY OWNER INSTRUCTION, 2026-09-22 — THE RE-PROFILE CANNOT BE RUN AND THAT IS NOT A BACKLOG STATE

**Owner, verbatim, relayed by `frankuser` while 7a was mid-run on the roofs
pair:**

> *"ok. stop gui testing lekkerzeilen for a while please"*

**So the finish-then-measure sequence above is blocked on HIM, not on a seat and
not on a measurement.** Recorded here because **a criterion nobody can satisfy
reads exactly like work nobody has done**, and in a month the difference is
invisible to whoever opens this file. Same reasoning as the `pylib.pas` section
being marked retired rather than deleted: the record of why a row stopped applying
is worth more than a clean file.

**SCOPE, AND NOBODY HERE WIDENS IT FOR HIM.** He named **GUI testing of
lekkerzeilen**. *"Stop"* is now, in-flight included; *"for a while"* is a pause,
not a cancellation. **He gave no duration and no reason and was not asked.** This
does NOT extend to compile-time work, to other demos, or to non-GUI lekkerzeilen
work — and if a seat asks whether it covers their case, the honest answer is that
he named GUI testing of lekkerzeilen and none of us should read further on his
behalf.

**READ THIS IN THREE SEPARATE PARTS. The first version of this paragraph ran them
together and the join was a scope claim in his voice — corrected 2026-09-22 after
`frankuser` caught it.**

1. **WHAT HE SAID, quoted, no gloss:** *"ok. stop gui testing lekkerzeilen for a
   while please"*.
2. **WHAT IS DEFINITELY UNAFFECTED, and this half needs no interpretation at all:
   a pause cannot un-measure anything.** The 19.7x against CPython, the four rows
   under MEASURED AS NOT THE CAUSE, and every measurement rule this ticket has
   paid for **all stand and stay citable.** This is the half the paragraph was
   really for — *"lekkerzeilen work is paused"* is one careless paraphrase from
   *"the lekkerzeilen findings are on hold"*, and expensively-bought facts stop
   being cited that way.
3. **EVERYTHING IN BETWEEN — non-GUI lekkerzeilen work — IS A QUESTION FOR HIM AND
   NOT A CONCLUSION EITHER OF US MAY WRITE DOWN HERE.**

**The earlier wording was "what is suspended is the production of NEW frame
numbers".** Both of us read that as the literal and correct reading of what he
said, **and it is still a permissive scope claim, which is the direction this file
may not move on its own.** Part 3 is exactly where a seat with a plausible case
will land, and **a file that already answers it removes the ask-him step** — which
this same file instructs everywhere else. **Ask him.**

**The first directive, which this supersedes on the TARGET and not on the
priority:**

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

    ratio at the medians      ->  19.7x, pxx against CPython
    (15 fps would be 66.7 ms = 8.0x; RETIRED as a target, kept only so the
     older rows in the table below can be read against something)

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

## THE SWEPT POPULATION IS A PROPERTY OF THE FRONTEND — A "2% TAIL" MEASURED ON `compiler.pas` DOES NOT DESCRIBE THIS PROGRAM

**Measured by `frankb-8e` at HEAD, banked at `c09551004` (verified on
origin/master), and recorded here because the next seat to read this umbrella
would otherwise inherit the wrong program class.** These are **SITE counts**, not
call counts — see the do-not-multiply section directly above.

Managed-local release sites by arm, x86-64:

| program class | `SXR_STR` | variants | records |
| --- | --- | --- | --- |
| `compiler.pas` | 23531 (99.3%) | 3 | 23 |
| NilPy with calls | 2387 (53.5%) | 1229 | 731 (16.4%) |

**`perf-a`'s own "the non-string arms are a ~2% tail" is correct for
`compiler.pas` and wrong for NilPy** — and **lekkerzeilen runs under nilpy**, so
the tail claim is about a program class this umbrella does not care about. 8e has
scoped the claim in its own ticket rather than leaving it standing. **Variants
plus records are ~26% of a NilPy program's release sites**, which is the
population `perf-o`'s carrier lives in.

**WHAT THIS DOES NOT SAY, and the boundary is the point:** it does not rank
anything. A site count is per CALL SITE — `frankh-c0` measured at HEAD
(`PXXDBG=a.ir`) that two `k.m(t)` sites mint two distinct unnamed carriers, and a
loop calling one method a million times reuses **one** slot. `perf-o`'s cost is
per CALL. **Multiplying a per-site population by a call frequency is this
umbrella's own do-not-multiply error arriving through a neighbouring
subsystem**, and the frame decomposition
(`task-e-decompose-a-lekkerzeilen-roofs-frame-...`) is still the thing that would
settle it.

**AND THE NUMBER ABOVE NEARLY CAME OUT THE OTHER WAY, WHICH IS WHY ITS
PROVENANCE IS ATTACHED.** 8e's first census answered `PXXVarClear` 58.6% and
`PXXStrDecRef` 0.9% — *a NilPy sweep is mostly variants* — which was **a
hypothesis this coordinator had supplied to that seat**. It was broken: the
x86-64 string arm does not call `PXXStrDecRef`, it calls `AnsiStrReleaseAddr`, a
compiler-emitted blob with **no symbol**, so a name-based census found 18
unrelated direct calls and missed all 2387. **Silence read as zero.** It was
caught by an unrelated byte signature answering 2387 against 18 — a 130x
disagreement between two instruments on one subject, with a clean negative
control. **Do not quote 58.6% from anywhere; it never existed.**

## THE PIN'S `pylib.pas` IS 135 LINES BEHIND HEAD — SO A RE-PROFILE MEASURES A NilPy RUNTIME THAT NO LONGER EXISTS

**RETIRED SAME DAY BY PIN v418 (`000425392`, binary `fda77c48b8ee`, source tip
`db6d1bddb`) — its own condition was "a pin carrying `be65bc3e3` or later" and
that is met. Re-checked here: `cmp` of the pinned `pylib.pas` against
`compiler/builtin/pylib.pas` is now IDENTICAL.** The section stays because the
MECHANISM recurs and the retirement is the evidence that it was real, not
because the gap is open.

**Measured here 2026-09-22, at the artefacts rather than from the handbook:**
`sha256sum` of `stable_linux_amd64/default/builtin/pylib.pas` against
`compiler/builtin/pylib.pas` differed, and `diff` counted **135 changed lines**.
(`frankuser` independently counted **137** as insertions-plus-deletions; two
instruments, two populations — mine counts changed lines on both sides, and
neither refutes the other.)
`$(PXX_STABLE)` consumers — every Track B and E demo, **lekkerzeilen included** —
get the PINNED one. This matters to this umbrella specifically because
**lekkerzeilen runs under nilpy**, so `pylib.pas` is its runtime, not a detail.

**Three commits touch it today and none of them is in the pin:**

- `be65bc3e3` — **nine more pylib temporaries that nothing released**
  (`franks-5b`). Per-pair and per-call leaks with measured byte counts:
  `TPyDict.most_common` 200 B **per pair** and linear; `pylist_setslice` 584 B
  rising to 1096 as **capacity** grows; the `pyiter_drain(pyiter_of_*(...))`
  family, seven sites, the four aggregates leaking **twice** (968 = 384 cursor +
  584 list). Eight fixture rows, each shown to FAIL on the unfixed compiler
  first.
- `8f1cf3341` — `%d`/`%x`/`%o` returned **a bare sign** for `Low(Int64)`.
- `185a81621` — `abs()` of `Low(Int64)` returned **a negative number**.

**THE TWO CORRECTNESS ROWS ARE THE ONES NOBODY FLAGGED.** The leak fixes change
allocation behaviour, which is what a frame decomposition would notice. The other
two are **wrong VALUES** that a demo built against the pin still produces today.

**CONSEQUENCE FOR `task-e-decompose-a-lekkerzeilen-roofs-frame-...`, and it is
not a reason to wait — AND SUPERSEDED BY v418, WHICH CLOSED THIS GAP:** a
decomposition taken on pin v417 was a true measurement
of the tree the demos actually run, and it is **not** a measurement of HEAD's
NilPy runtime. Say which, in the report. **NEVER WAIT FOR A PIN** — that is the
owner's standing rule and this paragraph does not soften it. What it asks is one
sentence of provenance, because a leak fixed at HEAD and absent from the pin is
exactly the kind of difference that turns up later as an unexplained delta in the
flattering direction.

**What would retire this row:** a pin carrying `be65bc3e3` or later. Re-derive
the 135 before quoting it; the two files move independently and the number is a
snapshot.

## THE npy IMPORT-COST EDGE IS REMOVED — IT IS A COMPILE-TIME TICKET AND THIS UMBRELLA MEASURES A FRAME

**Removed 2026-09-22 by the seat that wired it: `frankz-e5`. This is my own
error, and it is the error this umbrella already has a section about** — an edge
carrying p95 to work that cannot move the stated goal, which is exactly what
`franks-5b` found here this morning with the inverse-trig row, from prose
instead of from a lane mismatch.

`perf-n-an-imported-npy-module-costs-13x-per-function-versus-the-same-code-inline`
is a **compiler** ticket. Every mechanism in it is a parse-time scan —
`PyDefSiteMode`'s backward walk, `PyDefUsedAsValue`'s per-identifier compare,
`FindUClass`'s flat class-table scan — and its headline **38.72% on
lekkerzeilen** is 38.72% off the time it takes to COMPILE lekkerzeilen, not off a
frame.

**MEASURED, because a name is not the thing.** `FindUClass*` is declared in
`compiler/symtab.inc`; `PyDefUsedAsValue` and `PyClsAttrWriteScan` live in
`compiler/pyparser.inc` and `compiler/defs.inc`. A grep does put both names in
the EMITTED runtime — `compiler/builtin/pylib.pas` and `builtinheap.pas` — and
**all six of those matches are prose in comments**, which is this file's own
"a search for a NAME matches PROSE ABOUT the thing" arriving in the check that
was meant to settle it. Nothing in the emitted runtime calls them. The program
is compiled once and then runs; the scans cannot be in the frame.

**SO IT INHERITED p95 FROM A GOAL IT CANNOT SERVE.** Its own prio is 60 and that
is what it now ranks at — a 38.72% compile win ranks perfectly well on merit, and
the fleet's inner loop is a real beneficiary. **Nothing about the ticket is
downgraded; only the claim that it moves this umbrella's number is.**

**THE SCOPE QUESTION, SETTLED HERE RATHER THAN ESCALATED, AND THE AMBIGUITY WAS
MINE:** I retitled this umbrella from *"runs at 15 fps"* to *"lekkerzeilen
performance"* when the owner retired the target, and that broadened the title
past the evidence. **Every measured row in this file is a frame**: 1.887 fps,
530 ms, 19 windows, against CPython's 37.140. The owner's directive was about the
frame rate. **So this umbrella means the FRAME, and build time is a different
quantity that deserves its own umbrella if anyone wants one.**

**WHAT WOULD RESTORE THE EDGE:** a declaration that this umbrella's goal includes
build time, or a measurement showing one of these routines executing inside a
frame. Neither exists today. **Do not restore it on the strength of the ticket
being good** — it is.

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
   **THE LEVER IS ALIVE. A "DEAD" VERDICT STOOD HERE FOR ABOUT AN HOUR AND WAS
   RETRACTED BY THE SEAT THAT MADE IT** (`lekkerzeilen@507340f`; the earlier
   `83bb324` is superseded — **both shas are in the lekkerzeilen repo, not this
   one**).
   **What is established, proved off the binary rather than inferred:**
   unrolling `gfx.py:349` **alone** cannot flip the flag, because
   `platform/_sdl2.py:212` also holds it — arm Q unrolls `gfx.py`, leaving
   `_sdl2:212` as the only computed site in the tree, and the flag is still
   true. **What was mis-read as confirming that: arm R de-computes `_sdl2:212`
   TOO, and the flag goes FALSE** — 114,864 bytes of binary, **112,180 bytes of
   code**. That is an existence proof that the flag has an off switch.
   **AND THE OFF SWITCH IS SHIPPABLE, which is what makes this a live row:**
   `fn = getattr(lib, name)` → `fn = lib[name]`. `lib` is a `ctypes.CDLL` and
   `CDLL.__getitem__` is the documented lower-level accessor; **verified against
   the real library rather than reasoned** — both return `_FuncPtr`s wrapping
   the **same function address**, and `restype`/`argtypes` are assignable on
   both, which is everything `_declare` does with it. **It holds no `getattr`
   token at all, so it is invisible to the scan by construction.** With the
   `gfx.py:349` unroll, the tree reaches **zero** computed sites.
   **KEEP THIS OUT OF ANY RANKING: 112,180 bytes is a STATIC figure and nobody
   has measured what flipping the flag does to a frame.** This ticket has
   already made one 4x error converting a static win into a dynamic one. **7a's
   pre-registered prediction moves from UNSPENT to SPENDABLE and stands
   UNADJUSTED — under 37%, plausibly under 10% — deliberately not revised upward
   now that a big number is known to sit behind it.** That is what the
   pre-registration is for.
   **So the row reads: lever ALIVE, path identified and verified at the source
   level, runtime value UNMEASURED, A/B unbuilt and display-blocked. Not a
   ranked lever until it has a frame-rate pair.**
   **Two probe corrections, for anyone carrying numbers from that batch:** a
   fourth arm is **void, not null** — it planted a lex error in `_sdl2.py` while
   leaving `gfx.py:349` standing, so the flag was held regardless and no result
   could have discriminated. And a probe reported computed-getattr sites as
   **6/5/4** from a grep; **the true counts are 2/1/0. Do not quote 6/5/4.**
   **And there is NO program-wide builtin tax** — verified against the compiler
   source: `PyPyRangeAt` (`pyparser.inc:41776`) filters through `PyPathIsPython`,
   `.py`/`.npy` only, so planted `promocore.pas` and friends are skipped.
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
   **re-rank it, do not re-file it. UPDATED 2026-09-22 BY `frankb-8e`, AND THE
   UPDATE CUTS BOTH WAYS: THE CHEAP HALF IS DONE AND THE EXPENSIVE HALF IS NO
   LONGER A FIX.** This entry said the inline nil test was *"the cheapest large
   win on the board"* and *"UNSTARTED"*; both are retired.

   **DONE.** The SIZE half landed on six backends (−33% `.text`), and the inline
   nil test has now landed on **all six** as well — 3 bytes/site on xtensa, 4 on
   aarch64/riscv32/i386, 5 on x86-64, 8 on arm32. Measured **4.367 → 1.886
   ns/slot on x86-64, 56.8% against a 55.8% prediction.** The other five arms run
   under emulation here, so that is an x86-64 number and not a fleet one. **It is
   a per-slot microbenchmark and 8e has explicitly refused to attach it to a
   frame** — see the do-not-multiply section above; the frame decomposition
   (`task-e-decompose-a-lekkerzeilen-roofs-frame-...`, which this umbrella now
   `blocked-by`) is what would settle it.

   **NOT ONE MORE PUSH AWAY — DO NOT RANK IT AS IF IT WERE.** The remaining half
   is *skipping* the sweep, and `frankh-c0`'s measurement closed it in the
   direction that stops work: **`var_store` of a variant retains
   unconditionally** (verified by 8e at source, not on relay), so the carrier's
   release is **REQUIRED** and skipping it is a **leak** — the failure class no
   value assertion can observe. The MOVE variant was already built, measured with
   `objtrace` and **reverted on 2026-09-15**; the block above its grave calls it
   *"the fourth wrong predicate in this family"* and it segfaults a ten-line
   program, because a variant carried out of a virtual call is **BORROWED** and
   that is not visible in the node kind the predicate was reading.

   **8e's count is the part that should change the ranking:** five mechanisms
   (four live, one retracted) plus three backends that gave three different
   answers to one question before being unified — **five things serving one
   concept, *who owns this managed value*, and none of them states the
   invariant**; each infers it from a node's shape. That is
   `devdocs/dev/root-cause-over-microfix.md`'s own threshold (*two is a smell,
   three is a design flaw*) at more than double, and that doc's other half
   applies too: **the overhaul may be the SMALLER job, because it deletes cases.**
   **And the sweep's question is strictly harder than the four that were wrong** —
   they answer *"is this VALUE owned at a store"*, a property of a node; the sweep
   needs *"does this SLOT still own its referent at scope exit"*, a property of a
   **path**. So the remaining half needs **an ownership invariant in the IR, not
   an analysis**, and nobody is starting it today.

3. **`perf-b-the-inverse-trig-...`** — **SETTLED 2026-09-22 AND IT IS NOT A
   FRAME-RATE LEVER. Do not rank it here.** Double-double inverse trig at ~106
   bits in `lib/rtl/math.pas` where a scene needs ~24, and it does grow as a
   share under `--silent` (Dd\* 8 → 17 samples) **on `rijn`**. The share
   question did not need the roofs decomposition — it needed the call count, and
   7a had it: **`atan2` runs 1,258.4/frame on `rijn` and 46.0/frame on `roofs`,
   a 27x collapse** (`PROFILE-2026-09-21.md:222`). Against the **530 ms** frame
   (7a's quiet-box pair, arm B, 19 windows — 624 ms was the load-27-30
   reading and is carried as superseded, not replaced):
   **46 × 29,463 ns = 1.36 ms, 0.26%.**
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
   **THE `blocked-by` EDGE TO THIS TICKET WAS REMOVED 2026-09-22 and must not
   be restored.** It was still in this file's frontmatter while this very
   section said "do not rank it here", so the ranker went on inheriting p95
   to it and `tools/progress.sh next` dispatched a seat to it — which is how
   this was found. **Prose saying "do not rank" does not unrank anything;
   membership is the EDGE.** The ticket keeps its own prio 45 and is reachable
   on its own merits. If a roofs re-profile ever puts inverse trig above the
   noise, re-add the edge and say which measurement did it.

## perf-a AND perf-o OVERLAP RATHER THAN ADD — whoever measures second must SUBTRACT

Recorded here 2026-09-22 by frankb-8e, from frankh-c0's own analysis, **because
it is true of the PAIR and therefore belongs in neither ticket.** c0 said so
explicitly and then put it only in a message; a message is not a record, and
this board is the one place where someone would sum the two prizes.

- **`perf-a`** (managed-local sweep) is about whether a slot's release
  **happens at all**.
- **`perf-o`** (variant hidden-dest clear) is about how a release is
  **SPELLED** — `IRBuildHiddenDest` calls the portable Pascal proc with an
  argument node and a frame where `IR_VAR_STORE` calls the target's own blob
  with neither. Same semantics, same releases, same NUMBER of them.

**So they are not additive.** If the ownership invariant `perf-a`'s remaining
half now waits on ever lands and the sweep can skip slots, **the skipped slots
stop paying `perf-o`'s clear too** — the second fix's prize shrinks by whatever
the first one removed. Adding the two published figures would double-count the
intersection.

**Neither ticket can state this**, which is exactly why it kept nearly going
unrecorded: each is correct about its own subject and the overlap is a property
of the pair. **Whoever measures second subtracts, and says what they
subtracted.**

**Two further reasons not to size either from what is published today**, both
from the tickets themselves: `perf-o`'s asymmetry is **x86-64-local** (four
backends already call the portable proc from both paths; aarch64 has its own
helper), so it is not a six-arm prize; and `perf-a`'s landed win is a
**per-slot microbenchmark** figure (4.367 -> 1.886 ns/slot, 56.8%) with **no
frame share measured**. Both seats are holding their frame claims for the
decomposition wired above, and both are right to.

## The frame decomposition is wired HERE, not under the two tickets waiting on it

`task-e-decompose-a-lekkerzeilen-roofs-frame-...` (frankh-c0, `f1e9d0fa8`) is
added to this umbrella's `blocked-by` on 2026-09-22 by frankb-8e. It was wired
under `perf-o` already, and the suggestion on the table was to wire it under
`perf-a` too. **That edge would have been false and this one is not**, and the
difference is worth stating because the frontmatter is the only part the
ranker reads.

**`perf-a` is NOT blocked by it.** That ticket is proceeding on its own
evidence — all six backends landed, the population census done — and the only
thing held is a *frame-share claim*, which is a sentence nobody is waiting to
write. A `blocked-by` saying otherwise would be a summary-level falsehood in
the one field that routes people, and this board already has a dated instance
of prose and frontmatter disagreeing (see the removed inverse-trig edge above,
found because the ranker dispatched a seat to a ticket the prose said not to
rank).

**This umbrella IS blocked by it, and by its own text.** The section below says
of the variant-clear row: *"the question is does this cost anything in roofs at
all"*. The same question decides `perf-a`'s remaining half and `perf-n`'s two
rows. **An umbrella that cannot rank its own children until a measurement
lands is blocked on that measurement** — that is what the relation means here.

**It also ranks the work correctly rather than merely visibly.** Under
`perf-a` the producing ticket would inherit p70; under this umbrella it
inherits **p95**, which is right: it gates three children, not one. At its own
prio 45 it sits below every ticket it unblocks, which is the exact inversion
`effective_prio` exists to prevent.

**What would retire this edge:** the decomposition landing. Not a decision that
the frame no longer matters — the owner has retired *15 fps* as a number
(*"not written in stone, just a wishful figure"*), and that changes the target,
not the need to know where the time goes.

**AND AS OF 2026-09-22 THAT RETIREMENT IS PAUSED BY THE OWNER, NOT PENDING A
SEAT** — *"ok. stop gui testing lekkerzeilen for a while please"*, 7a stopped
mid-run. See the PAUSED BY OWNER INSTRUCTION section above for the scope. **This
edge is not stalled, unowned or deprioritised; it is waiting on a decision only he
can make.** Do not read its age as neglect and do not re-rank it on the strength
of nothing having happened. `frankh-c0` held `perf-o` in `working/` against this
row's dispatch date; that date no longer exists, and whether to park it properly
is c0's call, which it has been told directly.

## The variant-clear row is being tested for RETIREMENT, not for a fix

`frankh-c0` holds `perf-o-the-variant-hidden-dest-clear-...` (own prio 35,
effective p95 through this umbrella) and is **starting from the ticket's
retirement condition.** Its only evidence is two synthetic rows — +14% on 6M
bare method calls, +8% with allocation — and **the ticket says in its own text
that neither says what a demo pays.** So the question is *does this cost
anything in roofs at all*; **if it does not, a p95 comes off this board for
free.** A row deleted on a measurement is worth as much here as one fixed.

**It is deliberately NOT running the demo itself**, because two demos on one GPU
halve each other's frame rate **while producing a plausible table** — a second
run would contaminate 7a's as well as its own. 7a has accepted the ask and will
either report the share with the scene named **or say plainly that it could not
separate it**, rather than manufacture a number to fit the question.

**AND THE MEASUREMENT IS DELIBERATELY TAKEN IN THE EXPENSIVE REGIME, WHICH IS
THE METHODOLOGICAL POINT WORTH COPYING.** Dispatch and boxing are **not
independent** in the binary being measured: `PyModuleHasComputedGetattr` is
currently true, so every method takes the function-object ABI. 7a recommended
measuring on the **current** binary anyway, because **the asymmetry runs in
c0's favour — if dispatch is small on the boxed ABI it is small on the cheap
one too, so one run can RETIRE the row but cannot PROMOTE it.** That is exactly
the shape a retirement condition wants, and it means the confounded binary is
the *right* instrument rather than a compromise.

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

**NOT a frame time any more — the owner retired that target.** What retires this
umbrella is **a fresh profile of a ROOFS frame, taken after the current known
perf issues have landed**, naming the main performance issues it finds.

**THE TREE THAT PROFILE MUST SIT ON IS PIN v418** (`000425392`, binary sha256
`fda77c48b8ee`, source tip `db6d1bddb`), **superseding v417 after 100 minutes.**

**CHALLENGED AND RE-VERIFIED AT REF LEVEL 2026-09-22.** `franks-5b` measured its
own disk and reported the pin as v417 / `734d10ec7b53` — correct about that
checkout, which had not pulled `000425392`. At origin:
`git show origin/master:stable_linux_amd64/default/VERSION` -> **418**, and
`git show origin/master:.../stable_pinned | sha256sum` -> **`fda77c48b8ee`**,
matching `last.sha256` and `history.log`'s newest row
(`2026-09-22T12:31:26Z v418 fda77c48b8ee... db6d1bddb`). 5b's pair is exactly
v417's blobs (`git show 2b1a54397:...`). **Both rows are real and they measure
different trees.** Carried rather than replaced, and the method is the point:
`sha256sum <path>` answers about your last pull even when the identity you match
is unforgeable, and `VERSION` cannot disagree with the binary because one commit
writes both — **use `git show <ref>:<path>` for this question.**

**ATTRIBUTION NOTE, because the pin's own body is wrong and cannot be edited:**
`000425392` says *"lekkerzeilen-7a found (838e8eb45)"*. `838e8eb45` is
**`frankZ`** (`tools/whose_commit.sh`, rc=0, confirmed independently by its
author). The chain was **`franks-5b` flagged its leak fixes were inert until a
pin -> `frankZ` verified at the artefacts and wrote it up -> `frankuser` cut the
pin**. 7a's catch is the EARLIER one, v416/v417. Recorded here rather than by
rewriting history, which is unavailable (2,945 files in `done/` cite shas). It
matters because *"one seat caught this twice"* and *"three seats each caught it
once"* are different facts about **how this gets found**, and only the second
argues for a criterion rather than for a person.

**AND THE REASON v418 EXISTS IS A CRITERION THIS SECTION DID NOT HAVE: A PIN IS A
BINARY *AND* A FROZEN COPY OF `builtin/**`, AND THE TWO HAVE SEPARATE STALENESS
CLOCKS.** v417 closed the gap between origin and the pinned BINARY. The same gap
was already open in the pinned BUILTIN SOURCES — `pylib.pas` 135 lines behind —
and **a seat checking "is my fix in the pin" by the binary's provenance answers
YES while the builtin half is behind.** One pin closes both, but only at the
moment it is cut. `frankuser`'s framing, and it is the sharp one: this is
*"origin is not the pin" recurring one layer down.*

**SO THE CRITERION IS NOW: a re-profile must name the pin's BINARY and the pin's
`builtin/pylib.pas`, and say they agreed.** What made it urgent rather than
tidy: `be65bc3e3` is a LEAK fix, and **leaks are the class a performance profile
mis-measures** — leaked temporaries land in the allocator and heap-lock rows,
two of the largest rows in the profile this umbrella is about to rank from. A
roofs decomposition against v417 would have attributed an already-fixed leak to
the runtime and been quoted as *"after the fixes"*.

**v417's own record, kept because the pattern is the point:** `2b1a54397`,
binary sha256 `734d10ec7b53`, source tip `819aab1db`. **Verified here by reading
the pinned binary off disk after a pull, not off the commit message.** Cut
specifically to unblock this re-profile: 7a caught that `6b8b45af4` and
`247260d36` were on origin but **NOT in the pinned toolchain**, so a profile
taken before it would have measured **v416** and been quoted as *"after the
fixes"*. Graded `reds(1)` for the known atan differential, attributed and
awaiting the owner's contract call.

**AND A PROFILE ON A CONTENDED BOX DOES NOT RETIRE THIS EITHER.** 7a checked and
found **3,789 MiB of VRAM in use with a live remote-desktop daemon**, and
declined to run on a relayed *"he is out"*. **It has already published two
contended numbers today**, which is why its own refusal is the standard here
rather than a courtesy. That is
his sequence stated as a criterion.

**If anyone still wants the old bar for comparison:** a median at or under
**66.7 ms on `world/roofs`**, windowed, vsync ON, audio ON, **on a quiet box** —
the same configuration as arm B above — with
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
