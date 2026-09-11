---
track: T
prio: 45
type: bug
blocked-by: []
summary: "~182 slug-shaped ticket citations in `compiler/**` and `lib/**` comments resolve to NO file under devdocs/progress/ (2107 DO resolve, which is the positive control). THE COUNT IS NOT THE DELIVERABLE AND IS NOT REPRODUCIBLE: this ticket first said 177 after four matcher corrections; a reimplementation from this ticket's own description gave 195, and three MORE corrections brought it to 182 — seven, not four. A checker MUST carry a baseline (a bare one is a gate that cannot pass) and MUST use SYNTHETIC controls: both real-row controls this ticket originally named went stale within 90 minutes. Two dangling shapes exist and the screen cannot separate them — a comment justifying a LIVE refusal, and a FIXED bug's slug left behind; one verified instance of each."
status: backlog
---

# ~182 slug citations in `compiler/**` and `lib/**` resolve to no ticket

**Found by frankB 2026-09-11** (one instance, chased from a comment whose premise
was false), **population measured here the same evening, twice, disagreeing.**

## The sharp shape, and why it is worse than a stale fact

`compiler/pyparser.inc:23973` cited
`bug-a-nilpy-enumerate-over-str-inline-param-leak` while guarding a LIVE
refusal — `enumerate()` over a `str` is rejected outright — and the comment's
justification was that the leak is filed. It was not. **frankB has since FILED
it** (`16b387e33`, `backlog-core/`), so that row now resolves.

**A comment asserting that PAPERWORK EXISTS is checkable and was false**, and a
cited slug is worse than an unsourced claim: a slug *looks* checkable, so a reader
stops at the sight of it rather than at the sentence. The citation is what buys the
trust.

## TWO DANGLING SHAPES, AND A SCREEN CANNOT SEPARATE THEM

This is the prio question and it now has an answer in SHAPE, not in count.
49 of the 182 sit within ±6 lines of a refusal-shaped token
(`CompileError|Error(|Raise|refus|reject|not supported`). That is a **SCREEN, not
a verdict** — I read two of the 49:

| shape | verified instance |
| --- | --- |
| **(a) justifies a LIVE refusal** — the guard's stated reason is a filing that does not exist | frankB's `pyparser.inc:23973` (now filed) |
| **(b) a FIXED bug's slug left behind** — the comment documents the FIX and the slug names the defect | `compiler/pyparser.inc:28874` cites `bug-nilpy-assert-statement-not-supported` on the comment for the code that IMPLEMENTS `assert`. Measured: `assert x > 0` compiles and runs, exit 0. |

**(b) is the benign majority and it is still a defect of the same kind**: a reader
greps the slug, finds nothing, and **cannot tell which shape they are holding** —
whether the feature is the bug or the fix. (a) is the one that justifies a live
behaviour on absent paperwork. Separating them is a per-row read, unbounded, which
is why frankB declined to sweep and filed instead.

## The population — and the number is NOT the deliverable

| | run 1 | run 2 (independent reimplementation) |
| --- | ---: | ---: |
| distinct citations | 2400 | 2323 |
| **resolve** | 2058 | **2107** |
| resolve as PREFIX only | 21 | 24 |
| author-ELIDED (`bug-a-foo-...`) | *not bucketed* | 10 (all 10 resolve by prefix) |
| **resolve to nothing** | **177** | **182** |

Run 1 was this ticket's original measurement at `041f279e1`. Run 2 was written
**from this ticket's own description of run 1** and did not reproduce it. That is
the finding: **a census whose method is described in prose is not a census anyone
can re-run**, and the number moved 10% on a reimplementation by its own author the
same evening. Quote the corrections; do not quote the count.

## DO NOT BUILD THE CHECKER WITHOUT THESE **SEVEN** CORRECTIONS

Run 1's walk was 345 → 199 → 178 → 177. Run 2's was 195 → 182. Every step in both
was an instrument error, not a fix to the tree.

| # | correction | found in |
| ---: | --- | --- |
| 1 | citations **wrapped across comment lines** — the slug continues on the next line, so a line-scoped matcher captures a truncated prefix ending in `-` (146 of run 1's 345) | run 1 |
| 2 | slugs resolving as a **PREFIX** of a longer real filename (renamed or extended since the comment) | run 1 |
| 3 | **hyphen is not a word boundary** — `\bcompat-philosophy` matches inside `frontend-compat-philosophy.md`, which is not a ticket | run 1 |
| 4 | **stitch ONLY when the hyphen is the last non-space character of the line.** `or end == len(line.rstrip())` glues the next PROSE WORD onto an already-complete slug — this manufactured `bug-a-managed-locals-leak-at-for`, `bug-a-sizeof-real-for`, `bug-a-promoint-shr-yields-nothing-the` | run 2 |
| 5 | **the AUTHOR elided it.** `bug-a-promoint-shr-yields-nothing-...` is deliberate shorthand, not a dangling citation. 10 instances, **all 10 resolve by prefix** — which is the positive control that the shorthand was honest | run 2 |
| 6 | **uppercase inside a slug.** `bug-a-managed-locals-leak-at-ORDINARY-scope-exit-on-wasm32-...` is a real citation; an `[a-z0-9-]` body truncates it at the hyphen and the result then looks wrapped, feeding correction 4 | run 2 |
| 7 | compare **case-insensitively** against lowercase filenames, or 6 reappears at the resolve step | run 2 |

Corrections 4, 5 and 6 compound: 6 truncates the slug, which makes 4 fire, which
glues prose on, which produces a confident dangling row for a citation that is
perfectly correct in the source.

## CONTROLS MUST BE SYNTHETIC — both real-row controls went stale in 90 minutes

This ticket originally named two real rows: `compat-philosophy` must NOT be
reported (known false positive) and `bug-a-nilpy-enumerate-over-str-inline-param-leak`
MUST be reported (known true positive). **frankB filed the second one 90 minutes
later**, so a checker written to this ticket's specification is **red on arrival
for a matcher that is working** — an assertion written from a REPORT of the tree
rather than from the tree, and the report was mine.

frankB named the tension exactly: **the rows most useful as controls are the rows
most likely to move**, because a row is only interesting enough to cite as a
control once someone has looked at it, and looking at it is what gets it fixed.
Re-picking a different real row does not escape this — it only resets the clock.

**So the positive control is a PLANTED slug, not a found one.** The devtest points
the checker at a throwaway tree containing a source file with three citations:

- a **synthetic** slug that can never be filed (`bug-t-synthetic-control-...`) → must be REPORTED
- a slug that resolves → must NOT be reported (the over-block control: a checker that reports everything passes every test written about reporting)
- `frontend-compat-philosophy`-shaped text → must NOT be reported (correction 3)

A throwaway tree IS the right population: the checker's input is a tree of source
files, and the devtest supplies one. The live tree's number needs no hand-picked
row — the **baseline file** is the instrument there.

## Design

**The checker needs a baseline**, the way `tools/ast_slot_overloads.py` carries
`test/ast_slot_writes.expected`: snapshot the ~182 and red only on a NEW
unresolved citation. A bare checker over 182 legacy rows is a gate that cannot
pass, which this repo already names as not a gate at all.

The rule to enforce is frankB's: **cite a slug or do not claim the filing, and the
slug must resolve to a file.**

## Rejected reasoning, recorded so nobody re-derives it

I nearly picked a control on the grounds that short-form slugs
(`bug-ctor-managed-string-arg`, no track letter) are a DEAD naming era and so can
never be filed. **Measured: 1461 of 3589 real ticket files are short-form.** The
convention is alive and that control would have been stale-able too.

## PRIOR ART, AND IT ALREADY DECIDED THE HARD HALF

`tools/progress.py:2143` already ships a **DANGLING-LINK** aperture — same
question, different population: wiki-links inside ticket BODIES under
`devdocs/progress/`. It fires today (live example in a clean `check` run:
`bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython` names two
dangling links). So this ticket is an **extension of an existing instrument**, not
a new tool, and its five-outcome triage prose (rename / never filed / already
delivered / merged / never a ticket) is exactly the triage the ~182 need.

**And it already refused the matcher I spent the evening debugging.** Its own
comment: *"Only explicit `[[...]]` links are flagged: **the bare-slug regex
matches too much prose to carry this without noise**, and a wikilink is
unambiguous intent to point at a ticket."* frankD judged that in August, for
MARKDOWN. My seven corrections are the empirical measurement of that judgement on
a harder population — Pascal comments, where there is no `[[...]]` to key on and
prose wraps mid-slug.

**That changes the recommended fix.** Two options, and the second is cheaper:

1. A seven-corrections matcher plus a baseline file. Works on the tree as it
   stands; the matcher is the maintenance burden and every correction above is a
   red-on-valid-rows waiting to return.
2. **A CONVENTION: cite a slug in a comment in a recognisable form** (a `[[...]]`
   or a `see:` prefix), which makes the matcher trivial and the noise problem
   disappear — at the cost of touching ~2100 resolving citations, or of the
   checker only covering citations written after the convention lands.

Option 2 with a FORWARD-ONLY scope is the cheap intersection: no sweep of the
2100, no baseline of 182, and the checker is a few lines that cannot produce any
of the seven errors. It catches nothing that already exists, which is what the
baseline was for anyway — the baseline's whole purpose is to red only on NEW rows.
**The 182 then stay a documentation-cleanup ticket with no instrument attached,
which is honest about what they are.**

Whoever takes this should decide between those two before writing code, and should
read `tools/progress.py` around line 2120 first — the noise call is already made
there and it was made correctly.

## The census is now a COMMITTED SCRIPT, not a paragraph

`tools/slug_citation_census.py` — reproduces the run-2 numbers above, documents all
seven corrections inline against the row each one fixes, and emits
`slug<TAB>file:line` per dangling row because a census that prints only counts
cannot be debugged. **Wired into nothing**, deliberately, until the
baseline-versus-convention question above is decided.

It carries the negative control (`compat-philosophy` must not be reported) and a
matcher-is-dead control (something must resolve), and **no real-row positive
control** — the comment says why: both real rows originally named here went stale
within 90 minutes. A planted slug in a throwaway tree is the only positive control
that cannot be fixed out from under the test, and that belongs with the checker,
not with the census.
