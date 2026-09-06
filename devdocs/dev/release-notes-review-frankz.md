# Review of `release-notes-beta-0.1-draft.md` — coverage layers, Zig/Rust counts

frankZ, 2026-09-06. **Re-measured, not read.** Two claims hold, one is now
factually wrong in a way that matters for a public document, and one thing I
supplied has been stripped and should go back.

Measured at `fc839afa5`, job table from `testmgr --tier full --list`.

## 1. Rust and Zig — the claim HOLDS, and the numbers are better than the prose

Draft: *"a handful of tests on one target each, against thousands on fourteen
for Pascal."*

Re-measured, unchanged from my earlier pass:

    .zig    6 rows    test-core only
    .rs    28 rows    test-core only
    .pas 2750 rows    14 targets

**Accurate.** "One target each" is exactly right and is the load-bearing half.
I would put the three numbers in, because they are stronger than the adjective
and cost a line — "a handful" undersells Rust at 28 and oversells Zig's spread.

One addition worth its space: both are marked **(X) experimental** in the
repo's own track table, so saying so is reporting the project's existing
position rather than making a new concession.

## 2. "Whole suites in no tier at all" — CONFIRMED, independently

Draft: *"wasm32 and two ESP configurations. Not a failure, not a skip, not
counted anywhere."*

    grep -c '^test-wasm32'  <full tier job table>   ->  0
    grep -c '^test-esp'     <full tier job table>   ->  0

**Zero jobs each.** This claim is fine and I would not soften it.

## 3. The riscv32 paragraph is STALE and now says false things

This is the one that must change before publication. The draft says twenty-eight
rows share one sentence, seven have ever been checked, **"that leaves twenty-three
nobody has looked at"**, and **"nobody has measured them"**, and that one row
*"hangs forever"*.

All four are now false. The rows were measured against the oracle on 2026-09-06
(`fc839afa5`); the hang was fixed at `cc7ec7dce`; and `819291c36` has since given
every row its own reason, so there is no longer one shared sentence to count.

**Publishing "one row hangs forever" would ship a defect claim that was repaired
hours earlier.** Drop-in replacement:

> **A concrete case, and it moved while this document was being written.**
> Twenty-five riscv32 rows shared one sentence — *"backend feature gap"*.
> Measured against the x86-64 oracle, every row: **it was true of two.**
> Twenty-one build, run and match byte for byte. One is correctly skipped for
> the wrong reason — it prints raw addresses and a pointer-width-dependent size,
> so it can never match an oracle on any 32-bit target. Each row now carries its
> real reason. **They are still skipped**, because nothing has been wired to
> enforce them yet — which is a different sentence from "they do not work", and
> the difference is the whole point.

That is a **better** story for a release than the draft's, not a worse one: the
honest shape is that we audited our own coverage claim and found it wrong,
rather than that we are sitting on twenty-three unknowns.

## 4. My layer-1 scope has been stripped, and it inverts the advice

The draft says continuous testing *"reports failures and skips-it-knows-about,
and both are counted"*, then lists two uncounted categories. **The scope I
measured is missing, and without it a reader looks for silence in the wrong
place.**

Measured tonight, on `test-fpjson#00`: the harness is **loud** at the row level —
it printed `!! CORPUS MISSING — 1 job(s) will SKIP, not run`, named the missing
corpus, and stated outright that passlike scoring is not a pass. Exactly one line
misleads, and it is the one a reader quotes:

    testmgr: GREEN

A run whose only job did **not run** reports GREEN, because nothing failed. Add:

> Read the rows, not the verdict. A run's verdict is computed over the jobs that
> RAN and is printed in the same shape as one computed over all of them, so a run
> whose only job was skipped still says GREEN. The per-row lines are explicit
> about what did not run; the summary line is not.

This is not a criticism of the harness — at the row level it is louder than most
reds. It is a statement about which line a reader will quote.

## 5. The `ok:`-with-no-output section is mine and is correct as written

Byte counts differ from my report only because a different program was used.
The mechanism, the `rc=0`, and the advice to test for the artefact rather than
the exit code are all right. **Leave it in.** It is the single most actionable
thing in the document for anyone scripting `pascal26`.
