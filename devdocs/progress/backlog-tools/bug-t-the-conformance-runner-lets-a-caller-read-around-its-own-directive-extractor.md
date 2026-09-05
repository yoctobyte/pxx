---
slug: bug-t-the-conformance-runner-lets-a-caller-read-around-its-own-directive-extractor
title: "Three ways to misread a conformance row, one cause: the directive extractor is advisory, not a gate"
track: T
prio: 45
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "run_pascal_conformance.sh has a directives() extractor that has been right every time, and nothing makes a caller go through it. In one session three different misreadings each came within one step of converting a defect into a green row: a lower-case `{ %fail }` a grep missed, `--retry-skips` reporting exit-clean as PASS when the harness never compares output, and `fpc built no binary` read as unit-shaped when fpc was REJECTING the program. Three disguises, one cause. Proposal: a row cannot be unskipped without the extractor and an fpc OUTPUT diff."
---

# The three misreadings, all from 2026-09-05, all by one session

Each was caught, none by the harness.

**1. A grep instead of the extractor.** Checking which burn candidates were
must-reject rows, a grep for `%FAIL` said 0 of 25. `directives()` said 1:
`tenum2` spells it `{ %fail }` in lower case and the extractor uppercases.
Burning it would have removed a must-reject row from the suite.

**2. Exit code read as correctness.** `--retry-skips` reports a skip-listed row
that now runs as "exit-clean". The harness compares the EXIT CODE, never the
output, so three of 24 candidates ran to completion printing the wrong thing
(`tarray2` printed a PChar as its pointer value; `tforin24` printed garbage
where fpc prints `Monday`; `tclass12a` printed double where fpc prints 80-bit
Extended). All three would have been burned into the pass count.

**3. "No binary" read as "unit-shaped".** Oracle-diffing rows that compile,
four came back with no fpc executable. That was read as "unit test, compile-only
agreement". **fpc produced no binary because fpc REJECTS them** — they are
`%FAIL` rows pxx wrongly accepts. Two causes, one observation, and the
discriminator is the directive block again.

# Why this is one bug and not three lessons

`directives()` was RIGHT all three times. It is the only thing in the tree that
knows what a row asserts. What fails is that it is advisory: nothing in the
harness requires a caller to consult it, so every consumer re-derives the
question with whatever is at hand — a grep, an exit code, the presence of a
file — and each shortcut is wrong in its own way.

That is `devdocs/dev/normalise-dont-special-case.md` at the tool level, and the
same shape as *"calling the shared predicate is not the same as reaching the
shared answer"*. **A rule in a document does not fix it**, because the next
reader is exactly the person who did not know to look.

# Proposed shape — T's call, not the filer's

The suggestion, not a design: make unskipping go through one supported path
rather than through judgement.

- A mode that, for a named row, prints what the row ASSERTS (from
  `directives()`) alongside the pxx result and an **fpc 3.2.2 output diff**, and
  says in as many words whether the row may be removed from `pxx.skip`.
- `--retry-skips` should not be able to report a bare "exit-clean" list at all;
  its own summary already carries the caveat text, which is the weakest possible
  form of the fix and was written by the same session that then needed it.
- A `%FAIL` row and a unit-shaped row must be distinguishable in output, since
  "no binary" is currently ambiguous between them.

# Provenance and routing

Filed by frankA (Track P) from
[[feature-pascal-corpus-fpc-testsuite]], where all three misreadings happened.
**Not built here: Track T owns the tool.** Track T's session had ended when this
was filed, so it will sit until one is running — that is expected, not a stall,
and this note exists so nobody reads the delay as a blockage.

The related change already landed (`1984e6ba9`, `--retry-skips`, plus the caveat
wording in `5d6c169d1`); this ticket is about the gap that flag exposed rather
than the flag.
