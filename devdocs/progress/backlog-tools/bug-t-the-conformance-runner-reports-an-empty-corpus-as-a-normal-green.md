---
track: T
prio: 45
type: bug
status: open
blocked-by: []
owner: frankO
summary: "tools/run_pascal_conformance.sh guards a MISSING suite directory (prints SKIP) but not a PRESENT-BUT-EMPTY one: that prints `0 pass, 0 fail, 0 skip, 0 auto-gated (of 0)` and exits 0 — a line shaped exactly like a result, with `(of 0)` the only tell. Both cases exit 0, so a caller reading rc cannot separate no-corpus, empty-corpus and green. Measured on this box. 22 of 28 checkouts pass this target by absence, and the group that bit had `library_candidates/` present with the suite under it missing, so a presence check on the parent passes and the corpus still is not there."
---

# The conformance runner reports an empty corpus as a normal green

## Measured

`tools/run_pascal_conformance.sh ./compiler/pascal26 <dir>`:

| `<dir>` | output | rc |
| --- | --- | --- |
| absent | `test-pascal-conformance: SKIP — no suite at <dir> (run tools/install_lib_candidates.sh fpc-testsuite)` | **0** |
| present, empty | `test-pascal-conformance: 0 pass, 0 fail, 0 skip, 0 auto-gated (of 0)` | **0** |
| present, populated | `test-pascal-conformance: 381 pass, 2 fail, 133 skip, 34 auto-gated (of 550)` | 1 |

The `! -d "$SUITE"` guard at line 95 catches only the first row. The second is
the dangerous one: it is not labelled a skip, it is a summary line with zeros
in it, and it is what a differential measurement reads as "this axis costs
nothing".

## Why it matters here specifically

This is a **guard that cannot fail**, in the shape the handbook keeps
rediscovering. A before/after comparison across two arms both reading an empty
corpus **diffs clean**, and reports a widening as free on an axis that was
never exercised. That is not hypothetical: this ticket's author published
"row 1 fired zero times" against a directory holding no programs, and the
absence was real and in the wrong place.

`test/pascal-conformance/` holds only a 168-line `pxx.skip` — it is the skip
list, **not** the corpus, which lives in gitignored
`library_candidates/fpc-testsuite/tests/test`. So the natural presence check
looks at the wrong directory, and the checkout group that bit had the parent
present with the suite under it missing.

## What it should do

1. Separate the three states in the **exit status**, not only the text: no
   corpus, corpus present but empty, corpus ran. A caller reading `rc` alone
   currently cannot tell a green from a no-op.
2. Never print a `N pass, N fail` summary for a population of zero — say
   `NO CORPUS` and make it non-zero, the way `[ -x "$CC" ]` two lines below
   already treats an unusable compiler as a hard error rather than as 51
   per-test failures.
3. A positive control drawn from the right population: assert the runner
   **rejects** an empty corpus, so the guard is one that can fail.

Raised by frankD, who hit it from the other side — a checkout where `tdefault8`
passes by absence — and offered it either way; filed here because the
measurement above is this session's.
