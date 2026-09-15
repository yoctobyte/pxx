---
type: bug
track: N
prio: 70
status: open
slug: bug-n-the-demo-leaks-16-mb-per-two-minutes-on-a-real-world-and-it-is-not-in-the-render-path
---

# lekkerzeilen leaks ~16 MB per two minutes on a real world, and the RENDER PATH IS RULED OUT

**EVERY kB/s FIGURE IN THIS TICKET IS QUANTISED TO 8.5 kB/s AND THE DECIMALS
ARE NOISE — corrected 2026-09-15 after lekkerzeilen-c8 found the cause in their
own sampler.** It read `/proc` in kB and stored `int(total_kB / 1024)`, so each
sample discards up to 1023 kB before the slope multiplies it back up. Every
number below is therefore a whole number of MEGABYTES over 120 s wearing a
decimal, and the MB columns in the tables are the honest reading. The tell was
visible here the whole time and I wrote it into the ternary section myself —
*"a per-sample quantisation of 8.5 kB/s"* — and then went on quoting 136.5 to
one decimal in the headline, the slug and eleven other places. A resolution
noted in one section does not travel to the rest of the document by itself.

**The reproducibility claim needs the same haircut.** "136.5 in six legs,
identical to the last digit" is six legs that all landed in the SAME 16 MB
bucket. That is still a real agreement and it is agreement at 1 MB, not at
100 bytes; the digits after the point were manufactured by the unit
conversion.

Measured by lekkerzeilen-c8 on 2026-09-15. This ticket exists to own the NUMBER
and the list of things that have been eliminated, so the next bisect starts
where the last one stopped instead of re-measuring the render path.

All figures: `world=rijn` (four tiles), x11, 110 s warm-up, 120 s slope,
interleaved legs, same harness throughout.

## THE RENDER PATH CONTRIBUTES EXACTLY ZERO

Skipping ground, foliage, structures, traffic and the boat changes the leak by
nothing at all:

| skipped | run | t1 MB | t2 MB | kB/s (= the MB delta / 120s; decimals are an artefact) | cpu (jiffies/s) |
|---|---|---|---|---|---|
| NONE | 1 | 545 | 561 | 136.5 | 32.0 |
| ground,foliage,traffic,vessel | 1 | 549 | 565 | 136.5 | 29.7 |
| NONE | 2 | 545 | 561 | 136.5 | 31.9 |
| ground,foliage,traffic,vessel | 2 | 543 | 559 | 136.5 | 29.2 |

**Four legs, one number.** Every scene stage the demo draws for a world
contributes nothing measurable.

**SCOPED TO THIS WORLD, AND THE SCOPE IS LOAD-BEARING.** `rijn` has FOUR tiles
and everything is resident after `settle`, so nothing is streaming and the
render path is doing comparatively little. On a corridor with hundreds of tiles
streaming is live and the render path does far more work. **This negative does
not transfer to that case** and must not be quoted as "the render path does not
leak".

**Why the flat is trustworthy, which is the part that makes this bankable.**
A flat number is exactly what a stuck instrument prints, so it was checked
before it was believed: the `t1` baselines wander 543-549 run to run, so the
sampler is reading live values and it is the DELTA that is flat. And the
harness refuses to report unless the banner says the world loaded AND the probe
line says it skipped what was asked -- a no-op `--skip=` fails the leg rather
than printing a match. `lzworld` has now produced the same 16 MB bucket in SIX legs across
two independent experiments against a moving baseline.

**The frame-rate confound is measured, not argued away.** cpu goes 32.0 ->
29.7 jiffies/s when the entire world stops being drawn: an 8% change in work
done. The demo is not scene-bound on this world, so skipping the scene buys no
materially higher frame rate and the flat leak is a real flat rather than a
leak drop masked by an fps rise.

## TONIGHT'S COMPILER WORK CUT IT ROUGHLY IN HALF, AND THE CLAIM IS SMALLER THAN IT LOOKS

| binary | run | t1 MB | t2 MB | kB/s (= the MB delta / 120s; decimals are an artefact) | cpu (jiffies/s) |
|---|---|---|---|---|---|
| lz6 | 1 | 558 | 595 | 315.7 | 31.7 |
| lzworld | 1 | 543 | 559 | 136.5 | 31.9 |
| lz6 | 2 | 550 | 588 | 324.2 | 31.7 |
| lzworld | 2 | 545 | 561 | 136.5 | 32.2 |

Read the MB columns, which are the quanta: lz6 grows 37 and 38 MB, lzworld 16
and 16, over 120 s. Each sample truncates up to 1023 kB, so a delta of D MB is
D +/- 1.

**Reduction 53-61%, interleaved** — call it "a bit over half". The 57.3% that
stood here was 16/37.5 quoted to three figures off an instrument whose smallest
step is one of those megabytes.

The cpu column is what makes it safe: 31.7 / 31.9 / 31.7 / 32.2. Both binaries
do the same work per second, so neither is leaking less merely by rendering
fewer frames.

**THREE CAVEATS, ALL OF THEM NARROWING THE CLAIM, AND THEY TRAVEL WITH THE
NUMBER:**

1. **This is not "the object-lifetime work cut the leak 57%".** lz6 is compiler
   `44a006699586f064` at pxx HEAD `17e5731a7`; lzworld is `cfee5d6255237332` at
   `349c44e47`. The reduction is EVERYTHING landed between those two shas. Known
   contents: the OPERATOR fix (priced separately the same day, 2026-09-15, at
   lz6 2170.9 -> lz7 1641.8 kB/s on open water, 24.4%, against a pre-registered
   (those two survive the quantisation intact -- at ~255 and ~193 quanta a
   single-MB step is 0.4%, where at 16 quanta it is 6%)
   20% floor), plus `2dc0d6878` (the discarded class-result arm) and
   `4e1840d95` (the ternary fix). **Neither seat can apportion it without more
   legs, and the honest statement is that the range contains all three** --
   not that it is mostly one of them.

   The variant-carrier family is NOT in this range and by its own analysis
   could not be: it leaks references rather than bytes, so it cannot move a
   byte number in either direction. Its three failed attempts are therefore
   irrelevant to this figure and must not be netted against it.

   Recorded because both seats got this wrong in the same exchange, in opposite
   directions -- each talking the OTHER's contribution up, which is the same
   attribution failure as talking up your own and is harder to notice because
   it reads as fairness.
2. **lzworld carries the probe edits**: a module-level print and four
   `if ... not in _SKIP` guards evaluated per frame. With no `--skip` passed
   they change no behaviour, and four set-membership tests per frame cannot
   account for the gap -- 37 MB against 16 MB, so about 22 MB per two
   minutes, NOT the "183 kB/s" this line used to carry -- but it is a source
   difference between the two sides.
3. **137 kB/s is progress, not a fix.** A long session still grows without
   bound.
4. **STRUCK 2026-09-15 -- MEASURED AT ZERO, NOT NARROWED.** This caveat used
   to claim part of the reduction was wasted work stopping rather than a leak
   being fixed, and bounded the ternary fix's share at "a fifth to a third" of
   that gap from a census of fresh-literal arms. **That bound was wrong and
   is withdrawn rather than tightened.** Isolated directly, interleaved on
   `rijn`:

   | binary | legs | mean |
   |---|---|---|
   | `f5c08154dcac1f53` ternary ABSENT | 136.5, 136.5, 135.4 | 136.1 |
   | `cf9eac5905b3a912` ternary PRESENT | 136.5, 128.0, 136.5 | 133.7 |

   Difference **2.4 kB/s** against a per-sample quantisation of 8.5 kB/s
   -- i.e. both legs are the same whole number of megabytes, which is the
   strongest form this instrument can state a null in, and this line is where
   the quantisation was correctly named while the rest of the ticket ignored it
   (1 MB of arena over 120 s); two of three pairs identical to the byte, the
   single 128.0 exactly one quantisation unit below its partner; cpu
   31.8-32.4 on every leg, so no frame-rate difference. **Indistinguishable
   from zero, at most ~2% of the reduction and most likely none of it.**

   **WHY THE BOUND WAS WRONG, AND IT IS A REUSABLE ERROR:** it multiplied
   ~7 panels x 60 fps x 48 bytes as though every dict built by an untaken
   ternary arm SURVIVED. They do not -- the temp is a NilPy local, so it is
   ARC-eligible and a rebind in a loop releases the previous one. **Allocated
   is not leaked.** The untaken arm is real wasted work and contributes
   nothing to arena growth. The author had been told exactly this before
   building the bound and did not carry it into the arithmetic; recorded
   because the census was RIGHT ABOUT THE SIZE and WRONG ABOUT THE MECHANISM,
   and a prediction that misses low still misses.

## WHERE THE MISSING ~22 MB ACTUALLY LIVES

`f5c08154dcac1f53`, `cf9eac5905b3a912` and `cfee5d6255237332` all measure the
same 16 MB. So **neither the ternary fix nor the comprehension fix moves a
byte**, and the entire reduction happened in the range
`44a006699586f064` -> `f5c08154dcac1f53`: the operator fix, the receiver fix,
the four pylib fixes, and the discarded class-result arm at `2dc0d6878`.

**The ternary fix's value is the CRASH** -- `Stack.press` on any click into open
water -- **and not bytes.** It must not be credited with any share of the leak
reduction.

Note what this costs the earlier caveat about apportionment: the range is now
much better resolved than "nobody can apportion it", and the resolution came
from three archived compilers run against each other rather than from argument.

## WHAT IS LEFT, AND THE TRAP WAITING IN IT

On a settled four-tile world everything is resident after `settle`, nothing is
streaming, and nothing drawn leaks. So the world-specific portion is in
something the world causes to EXIST rather than something drawn per frame --
the per-frame simulation over what the world contains, or the water surface,
which has no skip on it yet.

**READ THIS BEFORE INTERPRETING THE NEXT FLAT NEGATIVE.** The `bug-n-a-method-
result-that-rides-the-variant-carrier-leaks-a-reference-per-call` family leaks
a REFERENCE, not bytes, and allocates nothing whenever the referent outlives
the loop. A settled world is precisely that condition: every referent is
resident. So if the residual 16 MB is that family, **a byte instrument reports a
flat number while the defect is present, and skipping the simulation will not
move it either.**

A second flat negative is therefore CONSISTENT with that family rather than
evidence against it. c8 named this trap themselves before walking into it,
having just been rewarded for trusting one flat number -- which is the exact
shape CLAUDE.md's "reading a NEGATIVE result" section is about. The water/sim
bisect is a test of the BYTE leak only and must be labelled that way.

## PROVENANCE

Every figure here is c8's, measured and quoted with the caveats they stated.
Filed in this tree at their request -- they measured it and declined to file in
a tree they do not commit to.

## 2026-09-15 evening — status from the lekkerzeilen seat, relayed by frankuser

**Measured by that seat, 2026-09-15 12:59, two interleaved rounds, same demo
source:** 131.4 kB/s at compiler cfee5d62 → 11.5 kB/s at 79551a1b, **91.3%
removed**, CPU identical across legs. A second instrument (`-dPXX_OBJTRACE`
birthplace census per vessel step) says 89.7% removed and puts the removed
bytes in the Vec3-returning contributor loop — the hidden-destination defect
fixed in `e59efc3f5` is the overwhelming candidate.

**Attribution, settled by the binaries (same seat, 19:20):** the runtime edit
in question added a NAMED function (`PyVarUserAug`), and every demo binary
carries a `.map`, so each arm can be asked whether it was built with it:
`lzwater_fix` (10:10, cfee5d62) ABSENT, 131.34 kB/s; `lzmid` (13:00,
cfee5d62) PRESENT, 131.25 / 132.79; `lzafter` (12:31, 79551a1b) PRESENT,
11.48 / 11.55. Two factors, one at a time: adding the runtime edit under the
old compiler moved nothing; moving the compiler with the edit present in both
arms removed the 91%. **The 91% is the compiler binary, by measurement.** The
lesson that seat wrote down: the emitted artefact is better provenance than a
build-time stamp -- where a fix adds a symbol, grep the map. `runtime_sha`
(hash of `compiler/builtin/*.pas`) stays in the build script so the next such
question is answerable up front.

**Re-measured on the 18:26 binary (compiler 1a74a2318642, builtin tree
4f69592e5), same seat, two interleaved rounds:** `lzafter` 11.73 / 11.36 kB/s
against `newbin` 11.20 / 11.30, CPU flat at 33-34%, load moving 2.8 -> 5.4
without moving the numbers. No regression, and `lzafter` reproduced its own
12:59 figure six hours later. Queue-death census on the same binary: 20/20
clean, BLOCKGET 0 -- the honest form is "frequent -> 0/20, twice", since the
~25% baseline has no counted census behind it.

**Residual:** ~11.5 kB/s. 21% of it is a small linear leak in the angular
integrator inside `Body.step` (`angular` region, 47.85 bytes per vessel step,
unticketed); the other 79% is in code that was never instrumented (`outside`
is the complement of the marker set, not a place), so no single cause can be
named for it. Unchanged on 1a74a2318642, so nothing since 79551a1b touched it.
**A named candidate for it, 2026-09-15 evening (frankuser):** the annotated-
local unbox landed at fc646c17a leaked one object per `g: Vec3 = mk()` (an
owned unbox on top of a retaining store -- 921 allocs, 0 frees in a loop,
value correct), and the demo writes that idiom per integrator step. Fixed the
same evening; NOT yet measured on the demo. See
`done/bug-n-an-augmented-store-into-a-class-field-of-a-variant-receiver-never-reaches-the-dunder`.

**Standing caveat from that seat:** an RSS slope cannot distinguish a repaired
leak from a premature free. Every figure above means "growth removed".

**Re-measured after 0badcd665 and 3a91d13f1 (lekkerzeilen seat, 2026-09-15
late evening, prediction P15 registered 19:25 before the push):** neither fix
moved the residual. Three arms, two interleaved rounds: `lzafter` (79551a1b)
11.33 / 11.52, `newbin` (1a74a231) 11.25 / 11.54, `lznew` (3aa02900de0f,
runtime_sha f2a20652c12a4580, the first arm with a runtime stamp) 11.38 /
11.62 kB/s; CPU flat at 31-33%. `lzafter` has now been measured six times
across three batches today, mean 11.50, full spread 0.40, which is what
licenses calling a 0.9% delta a null. The arms were shown to genuinely differ
by `runtime_sha` (0badcd665 adds no top-level symbol, so the `.map` trick
cannot see it; the two instruments are complementary). Growth still absent,
not a leak proven fixed. The residual -- `angular` at 47.85 bytes per vessel
step and the 79% in uninstrumented code -- is unchanged and unowned.
