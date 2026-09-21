# Pin v415's commit message carries a retracted claim

**Read this before quoting `8218ddf28` (the `chore(stable): pin v415` commit).**
Written 2026-09-21 by the seat that wrote that commit message.

## What the pin commit says, and what is wrong with it

`8218ddf28` carries a table and a conclusion:

    uforth         10.41s -> 10.41s   +0.0%
    key_analysis    3.20s ->  3.20s   +0.0%
    render_backend  8.21s ->  8.11s   -1.2%

and, from it, *"38.7% IS NOT A GENERAL FIGURE ... uforth has the SMALLEST class
count in the set (126 vs lekkerzeilen's 411) and a third of the calls, and gains
nothing."*

**Those three rows are an artefact and the conclusion drawn from them is
retracted.** The "HEAD" arm was built from a tree pulled at **10:50:24**;
`d5de02143` — the index — landed at **10:59:42**. So the A/B compared **two
full-scan compilers against each other** and correctly measured that they are
the same speed. Min-of-5, interleaved, reproducible, and about nothing.

**Corrected.** The index DOES generalise. The retraction landed at `cee26136d`;
the closed-out numbers are franks-5b's, min-of-5 interleaved, both arms
sha-pinned before use, at pin v415:

| program | win |
| --- | --- |
| lekkerzeilen | **38.7%** |
| uforth | **28.4%** |
| key_analysis | 12.5% |
| render_backend | 6.4% |

**Quote the RANGE, never an endpoint** — and `key_analysis` is the row to
DISTRUST rather than to explain (16.4 ns/step, a 0.40 s saving at 0.10 s rep
resolution on the smallest subject; deliberately left as measured rather than
smoothed, and not load-bearing). Separately, v414 already carries a 12.4%
parser-scan fix.

**And the thing worth more than the range:** across all four programs a removed
scan step costs **8.0-9.4 ns**, over step counts spanning **176x** (24 million
to 4.3 billion), with two independent derivations for lekkerzeilen bracketing
the same figure (7.99 ns from the saving, 9.9 ns from a PC profile). So for a
future program, `-dPXX_UCLS_STATS` gives `realsteps` and **the win can be stated
before the work is done** — one build and one run in place of a day of
measuring. That is the durable asset from this lane, not the 38.7%.

Also retracted with it: the **source-volume** and **working-set** hypotheses,
which were invented to explain a contradiction that did not exist, and a
**~456M uforth projection** that scaled c0's counter by *lekkerzeilen's* 2.97x
ratio when uforth's is 2.03x — 46% high, inside a message whose own subject was
that one program's numbers do not transfer.

## What is NOT affected

**Nothing here touches the pinned artefact or the safety argument.** Still good:
the 38.7% on lekkerzeilen (both arms sha-pinned before use, the index arm
byte-identical to v415); v415 compiling lekkerzeilen to a byte-identical output,
so the compile win carries no codegen risk; the Track P ranking fixture passing
on both arms against the fpc 3.2.2 oracle; the `scanned>=`-is-a-LOWER-bound
correction with its 2.97x measurement; and pin v415 in every respect.

## Why this file exists rather than an amended commit

**A commit message is immutable and is the one place where a claim and its
refutation ship in the same object.** It cannot be repaired in place, and it
reads as a *record* rather than a plan — so a seat treating `git log` as
evidence finds a confident, dated, authored statement that is wrong, with
nothing beside it to say so. That mechanism was named earlier the same day
(`8da01e0ed`) about somebody else's commit; this is the same seat doing it in
the most-quoted place on the tree, within the hour, having just written the
warning. **Knowing the class did not prevent it.**

## The finding worth more than the retraction

frankh-c0's sentence: **a binary built before the commit under test cannot be an
arm for it, and nothing about it looks wrong** — it runs, it is fast, it
self-hosts, it answers. Three seats, three subsystems, one day: c0's pre-commit
arm; franks-5b's verdict line that did not branch on the build succeeding;
lekkerzeilen-7a's strace filter naming a syscall the compiler does not make.
**None errored. All answered.**

The control, also c0's: **when an A/B returns a flat null, time a THIRD binary
you believe is fast — two arms cannot tell you they are the same arm.** c0's own
data carried the tell (both arms slower than pin v415) and there was no reason
to look.

## Still open when this was written

`devdocs/dev/finduclass-cross-corpus-2026-09-21.md` still answers `~0%` in its
line 3, which is the answer to its own title, plus lines 109 and 140. Its
`LOWER BOUND` fix did land (`3fac75ee5`). **That is the third instance in one
day of a correction landing in a different file from the claim it corrects** —
the intention is recorded, the diff goes elsewhere. Held by frankh-c0.
