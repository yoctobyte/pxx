---
type: bug
track: N
prio: 70
status: open
slug: bug-n-the-demo-leaks-137-kb-s-on-a-real-world-and-it-is-not-in-the-render-path
---

# lekkerzeilen leaks ~137 kB/s on a real world, and the RENDER PATH IS RULED OUT

Measured by lekkerzeilen-c8 on 2026-09-15. This ticket exists to own the NUMBER
and the list of things that have been eliminated, so the next bisect starts
where the last one stopped instead of re-measuring the render path.

All figures: `world=rijn` (four tiles), x11, 110 s warm-up, 120 s slope,
interleaved legs, same harness throughout.

## THE RENDER PATH CONTRIBUTES EXACTLY ZERO

Skipping ground, foliage, structures, traffic and the boat changes the leak by
nothing at all:

| skipped | run | t1 MB | t2 MB | kB/s | cpu (jiffies/s) |
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
than printing a match. `lzworld` has now produced 136.5 kB/s in SIX legs across
two independent experiments against a moving baseline.

**The frame-rate confound is measured, not argued away.** cpu goes 32.0 ->
29.7 jiffies/s when the entire world stops being drawn: an 8% change in work
done. The demo is not scene-bound on this world, so skipping the scene buys no
materially higher frame rate and the flat leak is a real flat rather than a
leak drop masked by an fps rise.

## TONIGHT'S COMPILER WORK CUT IT 57.3%, AND THE CLAIM IS SMALLER THAN IT LOOKS

| binary | run | t1 MB | t2 MB | kB/s | cpu (jiffies/s) |
|---|---|---|---|---|---|
| lz6 | 1 | 558 | 595 | 315.7 | 31.7 |
| lzworld | 1 | 543 | 559 | 136.5 | 31.9 |
| lz6 | 2 | 550 | 588 | 324.2 | 31.7 |
| lzworld | 2 | 545 | 561 | 136.5 | 32.2 |

lz6 mean 319.9, lzworld mean 136.5, **reduction 57.3%**, interleaved.

The cpu column is what makes it safe: 31.7 / 31.9 / 31.7 / 32.2. Both binaries
do the same work per second, so neither is leaking less merely by rendering
fewer frames.

**THREE CAVEATS, ALL OF THEM NARROWING THE CLAIM, AND THEY TRAVEL WITH THE
NUMBER:**

1. **This is not "the object-lifetime work cut the leak 57%".** lz6 is compiler
   `44a006699586f064` at pxx HEAD `17e5731a7`; lzworld is `cfee5d6255237332` at
   `349c44e47`. The 57.3% is EVERYTHING landed between those two shas. Known
   contents: the OPERATOR fix (priced separately the same day, 2026-09-15, at
   lz6 2170.9 -> lz7 1641.8 kB/s on open water, 24.4%, against a pre-registered
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
   account for 183 kB/s, but it is a source difference between the two sides.
3. **137 kB/s is progress, not a fix.** A long session still grows without
   bound.
4. **STRUCK 2026-09-15 -- MEASURED AT ZERO, NOT NARROWED.** This caveat used
   to claim part of the reduction was wasted work stopping rather than a leak
   being fixed, and bounded the ternary fix's share at "a fifth to a third" of
   the 183 kB/s from a census of fresh-literal arms. **That bound was wrong and
   is withdrawn rather than tightened.** Isolated directly, interleaved on
   `rijn`:

   | binary | legs | mean |
   |---|---|---|
   | `f5c08154dcac1f53` ternary ABSENT | 136.5, 136.5, 135.4 | 136.1 |
   | `cf9eac5905b3a912` ternary PRESENT | 136.5, 128.0, 136.5 | 133.7 |

   Difference **2.4 kB/s** against a per-sample quantisation of 8.5 kB/s
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

## WHERE THE 183 kB/s ACTUALLY LIVES

`f5c08154dcac1f53`, `cf9eac5905b3a912` and `cfee5d6255237332` all measure the
same 136.5. So **neither the ternary fix nor the comprehension fix moves a
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
resident. So if the residual 136.5 is that family, **a byte instrument reports a
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
