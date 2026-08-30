---
track: T
prio: 40
type: chore
blocked-by: []
summary: "A test expectation CAPTURED from a program's output records whatever the compiler did that day — bugs included — and then defends that behaviour after the fix, converting a defect into a requirement. Audit the Makefile's expect_same.sh values for which are DERIVABLE from the source independently and which are transcriptions of a run. test_alloca26 is the model of the safe form: 7088718 is reproducible by anyone, in any language, without running our compiler. File ownership is Track B where Makefile expectations are touched."
status: backlog
owner: unassigned
---

# Which test expectations were captured from output rather than derived?

- **Type:** chore (test-infrastructure audit) — **Track T**, with **Track B**
  file-ownership wherever `Makefile` expectations are actually edited.
- **Filed:** 2026-08-30 by frankB, out of
  [[audit-b-no-test-expectation-was-frozen-by-the-silent-pchar-alias-arm]],
  which answered the narrow version of this question and left the general one open.

## The mechanism

Most expectations here have the shape

```make
tools/expect_same.sh <name> "$$($(TESTTMP)/<prog>)" "<value>"
```

and `<value>` can arrive two ways. Either it was **derived** — computed from the
source, from a spec, or from an oracle — or it was **captured**: someone ran the
program, looked at what came out, and pasted it in.

A captured expectation records **whatever the compiler did on the day it was
written, bugs included.** That is not a dormant risk; it inverts the test. After
the bug is fixed, the test goes red, and the red points at the *fix*. The
suite has converted a defect into a requirement, and the natural reading of that
failure — "the change broke something" — is exactly backwards.

This is the same class the fleet has been finding all night in other registers:
an instrument that agrees with itself, a claim with nothing under it, a status
read off the wrong command. Here the instrument is the expectation, and it agrees
with itself because it was copied from the thing it is meant to check.

## Why it is worth a ticket rather than a note

The narrow audit that produced this found the silent `PChar`-alias arm had
frozen **nothing** — but only because the construct that triggers it is used in
exactly one place in the repo, and that place postdates the fix. That is luck
about one defect's blast radius, not a property of the suite. Every silent
wrong-value bug we fix from here has the same second-order hazard, and there is
currently no way to answer "which expectations could have been poisoned?" other
than reading them.

## The model of the safe form

`test_alloca26` expects `7088718` from `test/test_alloca.c`. That value is
reproducible **by anyone, in any language, without running our compiler**:
re-implementing the arithmetic in Python gives 7088718, and building the same
file with **gcc** and running it gives 7088718. Three independent sources.

That is the acceptance criterion for this audit, and it is worth more than any
individual finding it produces:

> **An expectation should be reproducible without running the implementation
> under test.**

Where that is achievable it removes the failure mode completely rather than
mitigating it. Where it is not — output whose only definition is "what our
compiler prints" — the expectation should *say so*, so a future reader knows it
is a transcript and treats a diff against it accordingly.

## Suggested method, and the trap in it

Read and judge; do not grep for a pattern. The narrow audit's own first pass is
the warning: searching for "pointer aliases" matched **180** declarations, of
which **8** were the construct that could carry the bug — `PRec = ^TRec` *defines*
a pointer type while `LocalPC = PChar` *aliases* one and inherits the element
type. A search term can name a syntactic shape while the defect lives in a
semantic distinction that shape does not carry, and the cost is not a miss, it
is 172 false positives — a real hit buried in that many near-identical lines gets
skimmed, and a negative result off that surface would have looked thorough and
been worthless.

Sensible ordering, cheapest signal first:

1. Values that are **self-evidently derived** — a factorial, a documented
   constant, a string the source assigns two lines above. Cheap to clear.
2. Values that are **bare large integers** or long opaque strings — the shape a
   transcription takes. The narrow audit judged all four such integers in the
   Makefile today and they were clean, so this is a small set.
3. Values whose expectation and program were **added in the same commit as a
   compiler fix** — most likely to have been read off the new behaviour.
4. Whatever remains: read it.

## Acceptance

Not "every expectation is derived" — some legitimately cannot be. Rather:

- each expectation is classifiable as derived or captured, and the captured ones
  are **marked as such** where they sit;
- any expectation found to encode a *wrong* value is fixed, and the ticket says
  which defect froze it;
- the convention is written down somewhere a future test author will meet it.

## Scope note

This does not gate anything and nothing is known to be broken. It is
prophylactic work on the suite's trustworthiness, priced accordingly — but the
mechanism is real and has already been demonstrated once in miniature, which is
why it is a ticket and not a paragraph in a message.
