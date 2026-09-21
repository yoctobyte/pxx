# Does the FindUClass index generalise beyond lekkerzeilen?

**No. It is ~0% on all three other Python programs that compile here.**
Measured 2026-09-21 (frankH) at frankuser's direction, because every number in
the original finding came from ONE program and this fleet had just spent a day
learning that a benchmark's SHAPE, not its size, decided whether a 9% win
existed.

## The two arms, named and hashed

    pin v414   sha256 aeadb1754b80b622   PRE-index   (source b109703344ea)
    HEAD       sha256 5c8c3b8a4c051337   index ON    (d5de02143 is an ancestor)

Verified as genuinely different files, and that `d5de02143` is an ancestor of
the HEAD arm — because two arms that are secretly one binary produce exactly
the 0% headline this document reports, and that had to be excluded before the
number could be believed.

**Precondition, per franks-5b:** both arms were checked with `--where` on the
`[RTL]` row (not a MISSING count — a healthy in-tree binary scores MISSING=2 by
design). Both passed. Run from the repo root, since a binary run elsewhere
falls through to a CWD-relative builtin lookup that resolves silently against
whatever checkout it lands in, and there are ~20 on this box.

**Do NOT use `-dPXX_UCLSIDX_OFF` as "before"** — 5b reports it carries the
parameterisation overhead of its own crosscheck (a branch on 1.45e9 iterations
plus a hash per call the real original never paid), and reported 50.7% where
the honest pin-vs-index is 38-41%.

## Result — interleaved, min-of-5, every value recorded

    uforth         pin reps: 10.81 10.41 10.61 10.81 10.71
                   HEAD reps: 10.41 10.41 10.61 10.61 10.81
                   min-of-N: pin 10.41s  HEAD 10.41s   +0.0%    (load 3.67)

    key_analysis   pin reps:  3.30  3.20  3.20  3.20  3.30
                   HEAD reps: 3.30  3.20  3.40  3.30  3.30
                   min-of-N: pin  3.20s  HEAD  3.20s   +0.0%    (load 4.23)

    render_backend pin reps:  8.41  8.21 10.04  8.31  8.21
                   HEAD reps: 8.21  8.11  9.43  8.11  8.21
                   min-of-N: pin  8.21s  HEAD  8.11s   -1.2%    (load 4.50)

Against **~38-41% on lekkerzeilen** (5b's measurement, its binaries, its tree).

**An earlier 3-rep pass reported -3.0% on key_analysis. That was noise**, and
it is recorded here rather than dropped: at 5 reps the same subject is +0.0%.
A three-rep min on a loaded box is not enough to separate 3% from nothing.

## MY PRE-REGISTERED PREDICTION WAS DIRECTIONALLY RIGHT AND ITS MECHANISM WAS WRONG

Registered before running: *"`UClsCount` is the import closure's class count,
so a program with a small import closure shows a much smaller share."*

The three programs do show a much smaller share. **But the proposed cause does
not survive the decomposition**, which 5b insisted on for exactly this reason —
total scan work is a PRODUCT, `calls x UClsCount`, and a null on the share
alone is ambiguous about which factor moved.

    program          UClsCount   FindUClass calls   scanned>= (LOWER BOUND)
    lekkerzeilen         411          3,860,000          ~1.45 B   (5b)
    uforth               126          1,240,000           153.7 M
    render_backend       240            160,000            25.2 M
    key_analysis         135            100,000             9.9 M

**uforth has the SMALLEST class count in the set and a call count one third of
lekkerzeilen's — and gains exactly nothing.** So neither factor alone explains
it: not class count (126 does more upper-bound work than 240), and not call
count (1.24M calls buys 0%).

**`scanned>=` IS A LOWER BOUND — CORRECTED 2026-09-21 BY franks-5b, AND THE
CORRECTION MAKES THE NULL HARDER, NOT EASIER.** This section first said UPPER,
which was wrong and would have let a reader dissolve the puzzle. Verified in
`symtab.inc` rather than taken on report: `FindUClassImpl` runs up to THREE
scans plus two alias probes, and `PxxFUCIters := PxxFUCIters + UClsCount` adds
one scan's length ONCE per call.

    scan 1  routine-local types   ranks by ScopeHopsToProc; NO Exit in the loop
                                  body (the `if Result >= 0 then Exit` is AFTER
                                  it) -- so it runs to completion on EVERY call
    scan 2  current unit          only if 1 found nothing; CAN exit on first match
    scan 3  visible fallback      only if 1 and 2 found nothing; ranks by
                                  UsesRankOf, so full length
    plus    FindUClassAliasRow and a UClsAliasCount ranking loop

So true steps per call are **at least** `UClsCount` and can be ~3x it. uforth's
real figure is therefore **153.7 M to ~460 M steps**, not 153.7 M as a ceiling.

**The conclusion survives and strengthens.** Taking the counter as actual work
predicts uforth should spend seconds here; with the correction it predicts
MORE, and the wall clock still measures nothing. The gap between the bound and
the truth is where the answer is, and it is wider than this document first
said.

## HYPOTHESIS FOR 5b, NOT A RESULT: the index may track MISSES, not classes

A lookup that HITS can exit early; a lookup that MISSES must visit every
candidate. So the index would pay off where lookups miss.

    "no class declares ..." sites   lekkerzeilen 50 | render_backend 9 | uforth 0 | key_analysis 0

That is a count of distinct warning SITES, not of per-call misses, and it is a
proxy rather than a measurement. **Recorded as the next thing to test, not as
the finding.** If it holds, the qualifier is not "import-heavy programs" but
"programs with heavy dynamic dispatch", which is a different and smaller set.

## THE CONTRADICTION IS REAL AND IS NOT BEING SMOOTHED

A model where cost is proportional to scan steps fits lekkerzeilen (>=1.45 B
steps, 34.4 s saved, so ~8-23 ns/step) and **that same model predicts uforth
should save 1.5-4 s of 10.41 s. It saved nothing.** Two branches, and the
second is the uncomfortable one:

1. per-step cost differs by an order of magnitude between the two programs; or
2. **lekkerzeilen's 38.7% is not mostly `FindUClass` after all** — 5b's
   attribution rests on a FLAT PC profile, which by construction cannot see
   callers, plus the fact that `d5de02143` is the only behavioural commit
   between the arms.

5b is taking (2) seriously and is running a TRUE step counter (`PxxFUCReal`,
incremented inside each scan body) on lekkerzeilen to get ns-per-step directly
rather than inferred. The same counter on uforth decides it: **same ns/step
means the model holds and uforth genuinely does far less work than the product
suggests; wildly different ns/step means the cost is not the stepping.**

**AND THE INSTRUMENT WAS NOT UNWIRED — 5b checked its own best explanation for
explaining this away, and killed it.** The index ships as the DEFAULT arm
(`FindUClass` calls `FindUClassImpl(name, True)` with no define required;
`-dPXX_UCLSIDX_OFF` is opt-out). So the HEAD arm had it ON and the 0% is not a
disconnected instrument.

**One caveat against my own miss hypothesis, from 5b:** scan 1 has no early
exit, so a HIT in scan 1 still costs a full scan and only hits in scan 2
shorten anything. That makes "hits are cheap" weaker a priori than it looks.
The 50/9/0/0 warning-site proxy remains the most suggestive thing on the table
and remains a proxy.

## What this does and does not say

**Does:** the index is worth ~0% on uforth, key_analysis and render_backend, so
38-41% must not be quoted as a general figure for pxx compile speed.

**Does not:** say the index is not worth having. lekkerzeilen is a real target
and its win is real and measured. It also says nothing about programs not in
this set.

**Not measured:** lekkerzeilen in MY tree. It does not compile here — it needs
its own flags and dies at `MAX_PROC_PARAMS` on a >32-parameter C function from
the GL headers — so lekkerzeilen's figure is 5b's, on 5b's binaries, and the
absolute seconds above must not be compared against 5b's wall clock. Only the
ratios travel.


## Pin note

These arms are **pin v414** (`aeadb1754b80b622`) against HEAD-at-the-time
(`5c8c3b8a4c051337`). **Pin v415 landed afterwards** — binary
`94fddf62ee6af731`, source `0176aa3cebf24ef9` — and carries `d5de02143` among
eleven commits that went inert to live. So every figure here names a compiler
that is no longer the pin, and "the pinned compiler" means something different
after v415 than it does above.


## THE DECIDING MEASUREMENT — TAKEN 2026-09-21, AND IT KILLS THE STEPPING MODEL

franks-5b pre-registered the criterion before either of us had the number,
which is what makes this decisive rather than a story fitted afterwards:

> *"If realsteps comes back near 456M, then 456M steps cost uforth ~0s while
> they cost lekkerzeilen 3.6s, and (a) is confirmed — different ns/step, and we
> learn the cost is memory not stepping. If realsteps comes back at ~10M, the
> product arithmetic was simply wrong about uforth and my model survives."*

A true per-step counter (`PxxFUCReal`, incremented inside each of the three
scan bodies under `{$IFDEF PXX_UCLS_STATS}`) built with `-dPXX_UCLSIDX_OFF`,
run from the repo root:

    uforth.py         calls=1,240,000   scanned>=153,697,831   real=311,636,212
    lekkerzeilen      calls=3,860,000   scanned>=1,449,667,904 real=4,305,236,025  (5b)

**311.6 M, not 10 M.** The second branch is dead: the product arithmetic was
not wrong about uforth. uforth really does perform three hundred million class
scan steps, and removing essentially all of them buys nothing measurable.

**THE RATIO IS NOT THE SAME EITHER, AND IT CUTS THE SAME WAY.** uforth's
real/`scanned>=` is **2.03x**; lekkerzeilen's is **2.97x**. 5b projected uforth
at ~456 M by scaling with 2.97 — the measured figure is lower, so the
prediction was 46% too high and *still* an order of magnitude above the
surviving alternative. Scaling one program's scan-mix onto another is itself an
assumption, and this is the measurement that says by how much it is wrong.

### ns/step, and the assumption it rests on

    lekkerzeilen   34.379 s saved / 4.305e9 steps  =  7.99 ns/step   (~24 cycles @ 3GHz)
    uforth         <= ~0.1 s      / 3.116e8 steps  <= 0.32 ns/step   (~1 cycle @ 3GHz)

**A factor of at least 25.** State the assumption both numbers share: each
treats the A/B delta as removing *all* the counted steps. That is 5b's
assumption for lekkerzeilen and I have applied the identical one to uforth, so
the RATIO is robust to it even where either absolute number is not. My
`<= ~0.1 s` is the resolution of a min-of-5 interleaved A/B that read 10.41 s
against 10.41 s; it is a bound set by my instrument, not a measurement of a
small positive saving.

**0.32 ns/step is about one cycle, which is what a tight loop whose first test
is an integer length compare SHOULD cost when the data is resident. 7.99
ns/step is about twenty-four, which is what it costs when it is not.** That is
the shape of a memory stall, and it is 5b's own candidate (a): the per-step
cost is dominated by cache misses reading class-name bytes out of the string
pool, and pool size tracks **total source volume**, not class count.

### So the qualifier changes a third time, and this is the third time

It was "closure size" (mine, from the 50/9/0/0 warning-site proxy). Then "call
count x class count" (the product, 5b's). **Both are now refuted by the same
table**: uforth has the smallest class count, a third of the calls, 311 M real
steps, and gains nothing. The surviving candidate is **source volume**, because
that is what sets pool residency — lekkerzeilen pulls 23 modules plus GL
headers; uforth stays small enough to stay in cache.

**SOURCE VOLUME IS UNTESTED AND MUST TRAVEL LABELLED AS SUCH.** It is
consistent with every row here and it is the third hypothesis in two days, two
of which died. What would move it: a program with a LARGE source volume and a
SMALL class count. If the index wins there, volume is the qualifier; if it does
not, volume is dead too and the cause is somewhere none of us has looked.

### What is still open, stated as 5b states it

This does not by itself choose between (a) different ns/step and (b)
lekkerzeilen's 38.7% not being mostly `FindUClass`. It refutes the *stepping*
model under either. 5b holds (b) open on its own account because the 38.7%
rests on a flat PC profile, which by construction cannot see callers, and
because 38.7% already exceeded the 27% self-time figure. **A win of 34.4 s is
not in dispute; what produced it is.**
