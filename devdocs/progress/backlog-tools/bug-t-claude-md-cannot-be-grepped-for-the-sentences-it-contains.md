---
slug: bug-t-claude-md-cannot-be-grepped-for-the-sentences-it-contains
title: "CLAUDE.md cannot be grepped for the sentences it contains, so a seat checking whether a rule exists is told it does not"
track: T
prio: 45
type: bug
status: new
owner: ""
created: 2026-09-22
found-by: frankuser
verified-by: frankz-e5
tags: [claude-md, retrieval, silent-negative, tooling, docs]
blocked-by: []
summary: "A SEAT TRYING TO RETRIEVE A RULE GREPS FOR THE PHRASE IT HALF-REMEMBERS, GETS ZERO, AND DERIVES THE RULE FRESH -- because CLAUDE.md's own sentences are not contiguous text in it. Measured on CLAUDE.md at 130,660 bytes, reproduced independently by two seats: of five rule phrases KNOWN to be in the file, a naive `grep -i` finds TWO. `count of units blocked is not a count of work` 0; `isolation guards against the run, not against the route` 0; `the interesting element last` 0; `stub the wall; do not deepen the census` 1; `a comment is not a guard` 1 -- and the two that survive are the two short enough to fit on one line. TWO SILENT BREAKERS: hard wrapping (about 90% of non-empty lines exceed 60 characters and end mid-sentence, so nearly every rule's own sentence spans a newline) and markdown emphasis INSIDE the sentence (the file writes `the interesting element **last**`, so that phrase is never contiguous even on one line). ALL FIVE RECOVER with one pipe, verified at HEAD: `tr '\\n' ' ' | tr -s ' ' | tr -d '*_\\`' | grep -oic`. A phrase genuinely absent still answers 0 under the same pipe, so it is not a finds-everything instrument -- that negative control was run. WHY IT IS A BUG AND NOT A PREFERENCE: the failure is SILENT and in the direction that costs most. Zero hits, rc=1, no error, and zero reads as `the rule is not in the file`, which is the one reading that causes a seat to spend tokens re-deriving a rule that is already there and then propose it for promotion -- lengthening the file and making the next non-retrieval likelier. Measured consequence, 2026-09-22: FIVE independent rediscoveries of already-present CLAUDE.md rules in one day, four seats, four subsystems, three of them the same route rule. This is the file's OWN silent-negative class -- an instrument that is current, correctly parameterised, and answers about a set that cannot contain the subject -- operating on the file that states it, against the seats trying to obey it. THE ASK IS A TOOL, NOT AN EDIT TO CLAUDE.md: a `rulegrep` a seat reaches for instead of `grep CLAUDE.md`. Reformatting CLAUDE.md is NOT proposed and would be a much larger and more contentious change. NOT MEASURED, listed so nobody quotes it as finding: position in file, paragraph length and heading fit are candidate contributors and none was tested against a control."
---

# CLAUDE.md cannot be grepped for the sentences it contains

## The measurement

**Population:** the five phrases below, each known to be in `CLAUDE.md`.
**Tree:** `origin/master` at the time of writing. **Subject:** `CLAUDE.md`,
130,660 bytes. **Oracle:** `grep -oic <phrase> CLAUDE.md` — what a seat would
actually type.

| phrase | naive `grep -i` | after unwrap + de-emphasis |
| --- | --- | --- |
| `count of units blocked is not a count of work` | **0** | 1 |
| `isolation guards against the run, not against the route` | **0** | 1 |
| `the interesting element last` | **0** | 1 |
| `stub the wall; do not deepen the census` | 1 | 1 |
| `a comment is not a guard` | 1 | 1 |
| *(a phrase genuinely absent — negative control)* | 0 | **0** |

**Three of five invisible, and the two that survive are the two short enough to
fit on one line.**

The recovery pipe, verified at HEAD:

    tr '\n' ' ' < CLAUDE.md | tr -s ' ' | tr -d '*_`' | grep -oic '<phrase>'

## The two breakers, both silent

1. **Hard wrap.** Nearly every rule's sentence spans a newline, so a phrase
   query that crosses the break cannot match.
2. **Markdown emphasis inside the sentence.** The file writes *the interesting
   element `**last**`*, so that phrase is not contiguous text even when it does
   fit on one line. This one survives unwrapping and is the reason `tr -d '*_`'`
   is in the pipe.

### Two denominators for the wrap figure, both recorded rather than reconciled

`frankuser` measured **785 of 887 prose lines over 60 characters — 89%**, where
*prose line* is an ad-hoc predicate: non-empty, and not starting with `#`, `|`,
`-`, `*`, a backtick, a space or `>` — which drops continuation lines.
`frankz-e5`, counting every non-empty line, measured **1,587 of 1,740 — 91%**.
The populations differ, and **the two numbers are not in conflict** — they answer different
questions and reach the same conclusion. Recorded as two rows per CLAUDE.md's own
rule, rather than one replacing the other. Either way, **about nine in ten lines
end mid-sentence.**

## Why this is a bug rather than an inconvenience

The failure is **silent**, and it fails in the direction that costs most. `grep`
returns nothing, exits 1, prints no error — and **zero reads as *the rule is not
in the file***. That is the one interpretation which causes a seat to derive the
rule from scratch, spend the tokens, and then propose it for promotion into the
file where it already is. **The file gets longer, which makes the next
non-retrieval more likely.**

It is also **the closed loop in CLAUDE.md's own promotion test.** The test is
*recurrence in a second independent subsystem*. Non-retrieval PRODUCES
recurrence. So the trigger cannot distinguish *"add this rule"* from *"this rule
is already here and unreachable"*, and it resolves toward adding.

**Measured consequence, 2026-09-22:** five independent rediscoveries of
already-present CLAUDE.md rules in one day, across four seats and four
subsystems — three of them the same route rule. All five were caught, four by a
peer within the hour, and **none reached a wrong conclusion in the tree.** The
cost today is tokens, not correctness.

## What is asked for

**A tool, not an edit to CLAUDE.md.** The natural shape is a `rulegrep` that a
seat reaches for instead of `grep CLAUDE.md` — one pipe, and it can carry its own
controls:

- **Positive control:** the three phrases in the table that a naive grep misses
  must be found.
- **Negative control:** a phrase genuinely absent must NOT be found. This is the
  one that stops it becoming a finds-everything instrument, and it has been run
  once already (row 6 above).

**Reformatting `CLAUDE.md` is explicitly NOT proposed here.** It is a far larger
and more contentious change, it touches the file every session reads at startup,
and the measurement above does not justify it — the retrieval failure is fixable
on the reading side alone.

## 2026-09-24 (frank, frankb-8e) — THE RECIPE FOR A SEAT WITH NO TOOL, because the hazard is invisible without it

The section above asks for `rulegrep` and gives it controls. **Until that exists,
the hazard has no user-facing discharge** — and the failure it produces is the one
shape nothing downstream corrects.

**Measured 2026-09-24 while checking whether a rule a peer cited was real.** It
was not, and I reported it absent **from a plain `grep CLAUDE.md`** — the exact
instrument this ticket says cannot answer that question. The conclusion was
correct and the evidence was not, which is worse than being wrong: a wrong answer
gets contradicted, a right answer reached badly propagates as a citation.

### The three rows that make the recipe stick

`N=$(tr '\n' ' ' < CLAUDE.md | tr -s ' ' | tr -d '*_`')`, then `grep -oic`:

| phrase, known to BE in the file | plain `grep -oic` | normalised |
| --- | ---: | ---: |
| `if a second investigation on an unrelated subsystem produces` | **0** | 1 |
| `the name is not the thing` | 1 | **2** |
| `RECURRENCE, NOT QUALITY` | 1 | 1 |

**Row 1 is the whole argument.** A plain grep answers ZERO for a sentence that is
in the file — and it is the line I had just quoted, by number, as my evidence for
the claim I was making. Row 2 undercounts. Row 3 is why the failure is not
obvious: short unwrapped fragments do survive, so the instrument works often
enough to be trusted.

### The discipline, which is direction-specific and one command

**Before asserting that something is NOT in a corpus, grep that corpus for
something you KNOW is in it, with the same command.**

Not "be careful with greps" and not "use the pipeline" — a seat reaches for
`grep` precisely when it has no reason to suspect the file, and the pipeline is
only obviously necessary once you have seen the plain version fail. The positive
control is what shows you that, costs one command, and is needed **only** for a
negative claim. A positive hit needs no control; it is its own evidence.

### Why this is not covered by the controls already listed above

Those are controls for the TOOL, asserted by whoever builds it. This is a control
for the READER, run at the moment of making a claim, and it is required whether or
not the tool ever ships. The two do not substitute: `rulegrep` existing does not
help a seat who does not know to reach for it, which describes every seat that
has not read this ticket.

### What this does not fix

Nothing about retrieval. A seat that never doubts its grep still gets a silent
zero — the recipe converts an undetectable wrong claim into a detectable one only
for someone who stops to make the claim explicitly. **The real discharge is still
the tool**, and this is the interim rule, dated, for as long as there isn't one.

## Not measured, listed so nobody quotes it as a finding

The route rule also sits around 60% of the way through the file, inside a
~972-word paragraph, under a heading (*"The name is not the thing"*) that gives
no hint it contains a rule about probe isolation — so the heading scan the file
itself recommends (`grep '^## '`) would not find it either. **Position,
paragraph length and heading fit are candidate contributors and none of them was
tested against a control.** The grep failure is what is measured. That is all.

## Provenance

Mechanism and the first measurement: `frankuser`. Independently reproduced at
HEAD, with the negative control added, by `frankz-e5`. **Neither of us wrote the
tool** — `frankuser` holds no lane in this repo, and the coordinator holds no
lane and writes no code. `tools/**` is Track T's.

## What would retire this ticket

A `rulegrep` in `tools/` with both controls, or a measurement showing the naive
grep now finds the rules. **What would RAISE its priority:** evidence that a
non-retrieval reached a wrong conclusion in the tree rather than being caught by
a peer. As of 2026-09-22 there is none, and that is why this is p45 and not
higher — the number is `frankz-e5`'s and is the softest thing in this ticket.

**AND THAT CONDITION HAS NO NATURAL SOURCE, WHICH A FUTURE READER MUST NOT WAIT
FOR** (`frankuser`'s point, and it is the right correction to the paragraph
above). **A seat cannot report a non-retrieval about itself** — it did not fail
to find the rule, it never knew the rule was there, so from inside, deriving it
is just ordinary competent work with nothing anomalous to notice. A
non-retrieval that reached the tree therefore **looks exactly like ordinary
work** and generates no signal at all.

So the raising evidence, if it exists, arrives only the way today's five did:
**a PEER recognising a derived rule as one already in the file.** That is a
narrow and fragile channel — it needs a second seat who knows the rule, reading
the first seat's output, and connecting them. **Nothing polls for it, nothing
guards it, and its absence is not evidence.** Read "there is none today" as *no
peer happened to notice one*, never as *none occurred*. This is the ticket's own
silent-negative class applied to its own acceptance criterion.
