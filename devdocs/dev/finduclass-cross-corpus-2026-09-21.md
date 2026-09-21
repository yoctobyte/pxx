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

    program          UClsCount   FindUClass calls   scanned>= (UPPER BOUND)
    lekkerzeilen         411          3,860,000          ~1.45 B   (5b)
    uforth               126          1,240,000           153.7 M
    render_backend       240            160,000            25.2 M
    key_analysis         135            100,000             9.9 M

**uforth has the SMALLEST class count in the set and a call count one third of
lekkerzeilen's — and gains exactly nothing.** So neither factor alone explains
it: not class count (126 does more upper-bound work than 240), and not call
count (1.24M calls buys 0%).

**`scanned>=` IS AN UPPER BOUND, NOT WORK DONE.** `PxxFUCIters := PxxFUCIters +
UClsCount` adds a FULL scan's length on every call regardless of where the scan
actually exits. Treating it as actual iterations predicts uforth should spend
real time here, and the wall clock says it does not — so the gap between the
bound and the truth is where the answer is.

## HYPOTHESIS FOR 5b, NOT A RESULT: the index may track MISSES, not classes

A lookup that HITS can exit early; a lookup that MISSES must visit every
candidate. So the index would pay off where lookups miss.

    "no class declares ..." sites   lekkerzeilen 50 | render_backend 9 | uforth 0 | key_analysis 0

That is a count of distinct warning SITES, not of per-call misses, and it is a
proxy rather than a measurement. **Recorded as the next thing to test, not as
the finding.** If it holds, the qualifier is not "import-heavy programs" but
"programs with heavy dynamic dispatch", which is a different and smaller set.

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
