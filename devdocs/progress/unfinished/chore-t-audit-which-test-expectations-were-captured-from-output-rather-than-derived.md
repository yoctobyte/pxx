---
track: T
prio: 40
type: chore
blocked-by: []
summary: "A test expectation CAPTURED from a program's output records whatever the compiler did that day — bugs included — and then defends that behaviour after the fix, converting a defect into a requirement. Audit the Makefile's expect_same.sh values for which are DERIVABLE from the source independently and which are transcriptions of a run. test_alloca26 is the model of the safe form: 7088718 is reproducible by anyone, in any language, without running our compiler. File ownership is Track B where Makefile expectations are touched."
status: unfinished
owner: frankB
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


## Progress 2026-08-30 (frankB) — the NilPy population is DONE and self-enforcing

The audit has an instrument and one population is closed. Recording what is
settled, what it cost, and exactly what is left, because the remaining work needs
a different oracle rather than more of the same reading.

### The strong result: 342 of 353 NilPy expectations are DERIVED, proven

A NilPy test is a Python program, so CPython can run it. That turns this audit's
question from a heuristic into a measurement for the whole `.npy` population:
run each test under CPython and compare byte for byte against its `.expected`.
An expectation CPython reproduces **is** reproducible without running the
implementation under test, which is this ticket's criterion exactly.

```
NilPy expectations with a CPython oracle: 353
  DERIVED  (CPython reproduces the .expected) : 342
  transcripts (cannot be confirmed)           : 11
```

**Only one of the 353 actually disagrees with the oracle**, and it is not a
frozen compiler bug: `test_nilpy_math_domain_errors` holds the older generic
`ValueError: math domain error`, while CPython 3.12+ emits per-function wording
(`expected a positive input`). That is an error-MESSAGE difference, which
CLAUDE.md's compat table defers explicitly — *"our diagnostic/message/error
number differs → defer"* — and no working program changes behaviour on it. So it
is **labelled, not fixed**, which is the disposition this ticket asked for.

The other ten cannot run under CPython at all: four use syntax NilPy accepts and
CPython rejects (a language feature under the N charter, since upward
compatibility runs one way only), three need companion modules that exist only
under our import resolution, two read stdin, and one pins our behaviour where
CPython raises mid-iteration.

### The labelling is enforced, not asserted

`test/nilpy_transcripts.txt` lists all eleven with a reason each, and
`tools/expect_audit.py --oracle` enforces it **in both directions**: a test that
stops agreeing and is not listed is reported as a NEW TRANSCRIPT; an entry that
starts agreeing is reported as STALE; an entry naming a test that no longer
exists is reported too. Exit 1 on any drift, so it can gate.

**Verified that it actually enforces** — an enforcement tool that does not
enforce is precisely the failure class this ticket is about. Dropped a real entry
and added a bogus one in a single run:

```
NEW TRANSCRIPT (not in test/nilpy_transcripts.txt): test_nilpy_package_imports
REGISTRY NAMES A TEST THAT NO LONGER EXISTS: test_nilpy_no_such_test_at_all
registry: OUT OF SYNC
exit=1
```

Registry restored byte-identical afterwards.

### The triage instrument, for the populations with no oracle

`tools/expect_audit.py` (no flags) classifies the Makefile's inline expectations
by a mechanical signal: **does the expected text appear literally in the test's
own source?** A test printing `writeln('looped 3')` checked against `looped 3`
is derivable by inspection; a value appearing nowhere in its source is a
*computed* result, and computed results are where capture happens.

```
Makefile expectations parsed: 3063 of 3101 mentions (98.8%)
  low  (derivable by inspection) 1716
  med                             542
  HIGH (computed)                 805
.expected files: 477 — low 260, med 178, HIGH 25, no sibling source 14
```

It is a ranked reading list, not a verdict: it cannot know that
`15511210043330985984000000` is 25!, and it flags it. The point is to spend
judgement where capture is possible at all.

The 38 unparsed are 35 line-continuations, 2 non-calls and 1 line with a
trailing comment — stated because a coverage claim with an unstated remainder is
the shape this ticket exists to distrust.

### Two things NOT filed, because checking beat filing

- **Unwired `.expected` files.** The classifier reported 24 named nowhere in the
  Makefile, which looked like dead weight. Sixteen are corpus fixtures driven by
  `tools/run_fgl_corpus.sh` and friends, and `tools/check_test_wiring.py` — which
  already exists and already gates this — reports the whole tree clean. My
  "unwired" test was Makefile-only and would have filed a finding an existing
  tool already covers.
- **It did flag a file of mine**, though: `test/lib_mimic_xml_dom_minidom.npy`,
  banked earlier today and deliberately not wired because the shim it tests hangs
  the compiler. Registered in `test/UNWIRED.txt` with the reason and the
  condition for wiring it. The gate is clean again.

### What is left, and why it needs a different instrument

The Pascal and C populations have no oracle wired into this tool. The probes
exist — `tools/fpc_diff_probe.sh` and `tools/gcc_diff_probe.sh` — so the same
strong check is available in principle, but only for the subset that compiles
under FPC/gcc, which for pxx-dialect tests is a minority. So the remaining work
is: extend `--oracle` to the C corpus (where gcc is a genuine oracle for most of
it), and hand-judge the Pascal HIGH bucket, which the literal-overlap ranking has
already ordered.

Returned to `unfinished/` rather than held in `working/`: one population is
closed and enforced, the next needs a different oracle, and nothing is
half-applied.
