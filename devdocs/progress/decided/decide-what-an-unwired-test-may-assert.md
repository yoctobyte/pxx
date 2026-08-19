---
slug: decide-what-an-unwired-test-may-assert
track: U
prio: 55
status: backlog
---

# May we record our own output as the expectation?

**Read time: 3 minutes.** One principle question, three options, a recommendation.

## The measurement

`tools/check_test_wiring.py` found 98 test files no build rule runs. Ten had an
`.expected` sibling and shipped alongside a fix in the last two days; those are
wired now (`66de48a84`, `38a88a8b8`, `56edf4392`) and all pass.

Track T then triaged the remaining 85 in ~11 seconds (85 compile-only invocations
at ~0.13s each):

| bucket | count |
| --- | ---: |
| compiles today | 61 |
| helper module, correctly not a rule | 5 |
| blocked bare, but builds with the right flags | ~5 (synapse smokes need `--mimic-fpc -Fuexternal/synapse`; some want `-I`) |
| genuinely blocked | ~10 |

The ~10 carry a compiler error as their exemption reason — an observation, not a
summary — so `UNWIRED.txt` is the right home for exactly those.

## The fork

**None of the 61 has an `.expected` file.** The ten that did were the ten already
wired. So "trivially wireable" overstates it: they compile, but wiring one means
**deciding what it should assert**, and there is no recorded answer to inherit.

That is a principle question, not a chore:

1. **Record current output as `.expected`.** Fast — 61 files, mechanical, done in
   an afternoon. And it **cements whatever the compiler does today as correct**,
   including any bug. A test built this way cannot fail for the reason tests
   exist; it can only detect *change*, and it will defend a wrong value as
   loyally as a right one.
2. **Verify each against the reference implementation first**, then record: FPC
   for Pascal, gcc for C, CPython for NilPy. Honest, and the oracles and probes
   already exist (`tools/fpc_diff_probe.sh`, `gcc_diff_probe.sh`, `pydiff.py`).
   Slower, and it will surface bugs — 61 files against an oracle is a bug hunt
   wearing a wiring task's clothes.
3. **Assert only "compiles and runs without failing"** — no output comparison.
   Immediate, honest, records nothing false. Weak: it catches crashes and
   regressions-to-crash, nothing about values.

## Recommendation

**3 as the floor, 2 where an oracle exists, never 1.**

Option 1 is the one to rule out explicitly, because it is the tempting one and it
inverts what a test is for. This repo's whole method is differential — every
recorded wrong root cause here was a plausible story nobody diffed against an
oracle — and recording our own output as truth is that failure made permanent and
given a green tick. Worse, it is invisible afterwards: nothing in the file says
"this expectation was never checked against anything."

Then: C files largely self-assert (`assert()` / non-zero exit), so option 3 costs
almost nothing there and is genuinely sufficient. Pascal and NilPy files need an
expectation, so those get option 2 — and the bugs it finds are the point, not a
cost overrun.

If option 2's yield is too slow to absorb, the honest fallback is to wire fewer
files properly rather than all 61 cheaply.

## A fourth form, measured — the oracle check that does not expire

*Added 2026-08-17 by frank3, as a worked example rather than an opinion.*

`test/lib_mimic_warnings.npy` (and `test/lib_mimic_six.npy`) were wired this way
and it is worth naming, because it is option 2 with the verification made
**permanent instead of historical**:

> The test file is **valid CPython as well as valid NilPy**, imports the shim by
> its real module name, and asserts only on the subset both implementations
> agree on. So it runs two ways — `python3 t.py` and `pinned t.npy` — and both
> print the same 9 `=ok` lines.

Option 2 as written checks against the oracle **once, at wiring time**, and then
records the answer. That answer is right when recorded and silently ages: nothing
re-checks it, and if CPython's behaviour or our reading of it was wrong, the file
looks exactly like a verified test forever after. Same failure mode as option 1,
only delayed — which matters here because the ticket's own objection to option 1
is *"nothing in the file says this expectation was never checked against
anything."* A once-checked file says nothing either, past the day it was written.

Making the test dual-runnable turns the oracle from a step in a procedure into a
property of the file. It also forces the useful discipline: **you must decide
what the two implementations genuinely share.** Concretely, `lib_mimic_warnings`
asserts on stdout only, because stderr is where the shim deliberately differs
(CPython walks the stack and prints `<file>:<line>:`; we cannot). Asserting on
stderr would have encoded *our* format as if it were CPython's — option 1
smuggled inside option 2. The divergence is stated in the file's docstring, so
what is untested is visible rather than absent.

**Where it applies is narrow, and that is the honest part.** It needs a frontend
whose source is legal input to the reference implementation, so it is natural for
NilPy (CPython runs the file), plausible for C (gcc compiles it), and **not
available for Pascal** — an FPC-vs-pxx comparison needs two builds of one source,
which is `tools/fpc_diff_probe.sh`'s job, not a property of a single file. So
this does not replace option 2; it is the strictly better instance of it wherever
the source is dual-legal, and Pascal still gets option 2 proper.

One caution from wiring these: assert a **count** as well as the content
(`lib-test` greps `= "9"`). My first version asserted 10 `=ok` lines when the
file had 9 and lib-test went red — which is the check doing its job. Without it,
a test that silently stops emitting half its assertions still passes.

## What changes on each answer

- **3+2:** ~61 files wired over some days, a stream of new bug tickets, no false
  expectations recorded.
- **1:** all 61 wired this week, and an unknown number of bugs permanently
  blessed with a passing test in front of them.

---

# DECIDED 2026-08-19 by the user — **triage them, and it is Track T work**

> "Triaging it is. And I think this is Track T work, right?"

**Never option 1.** Recording our own output as truth is ruled out explicitly, for the
reason in this ticket: such a test cannot fail for the reason tests exist, and nothing in
the file afterwards records that its expectation was never checked.

## A cheaper path than any of the three options, found by measuring

The ticket framed this as "61 files x decide what each should assert", which is why it
looked like days of oracle work. **That over-costs it, because the files are not what the
options assumed.**

The user's question — *"whoever wrote them didn't think they were worthy?"* — was checked
against git rather than answered from the ticket. Every one of the **30 most recent
commits that added a file under `test/`** is a `fix(...)` or `feat(...)`:

```
fix(N): a backslash before a newline in a string literal is a line continuation
fix(N/A): a builtin type's method, called unbound
fix(A): a default argument was passed by value into a by-reference parameter
fix(A): @procvar is the pointer it HOLDS in delphi mode, not the variable's address
```

**These are repro tests written alongside real bug fixes, and never wired.** An omission at
the last step, not a judgement of worth. Two consequences:

1. **Deleting them is the WORST option, not the cheap one.** A repro for a *fixed* bug
   guards a failure that demonstrably happened once, in the exact shape that produced it.
2. **The expectation usually does not need deriving from an oracle — it is in the commit
   that added the file.** Minutes per file, not an oracle run.

## The procedure

1. For each unwired file, find the adding commit (`git log --diff-filter=A`).
2. **Fix/feat commit** → read what the bug was, wire the test to assert *that*, and
   **record the commit sha in the expected file** so the provenance is visible instead of
   lost. (This is the ticket's own objection to option 1 answered: the file now says where
   its expectation came from.)
3. **No fix commit, no ticket, no discernible intent** → that is the genuine leftover;
   deleting it is fine.
4. **Commit does not say what the right output is** → fall back to the oracle (option 2),
   or **park it and ask the owning lane** rather than guessing.
5. Where the source is legal input to the reference implementation, prefer the
   **dual-runnable** form documented above — the oracle becomes a property of the file
   instead of a step that expires. And **assert a COUNT as well as the content.**

**Caveat, stated because the sample was narrow:** the 30 sampled additions are recent
work. The older tail may be scruffier and should be sampled before assuming the whole 61
follow the pattern.

## Ownership — TRACK A (corrected by the user), and the lane choice IS the design

**First recorded as Track T; the user rejected that.** *"It may lead to a waterfall of
tickets. So if Track T is the wrong choice, make it Track A. And just sweep it — not a new
ticket for everything that was already ticketed and fixed."*

The reasoning generalises and is worth keeping: **T is bound by "T owns the tool, never the
bug", so under T every red MUST become a ticket for another lane.** Across ~61 files that
is a ticket factory whose handoff cost exceeds the work. **A can fix a red in place**, so
the identical job becomes a *sweep*. The lane choice, not the method, decides whether this
is one job or sixty-one.

**And most reds need no ticket at all:** these files came from fix commits, so the bug
already has a ticket **in `done/`**. A red is a regression of something recorded — a
reference, not a filing.

### Superseded: the Track T framing below



**Track T owns it:** test infrastructure, T already owns `tools/check_test_wiring.py`, and
T did the original triage of the 85.

**But "T owns the TOOL, never the bug" applies in full.** Some of these WILL go red when
wired — that is the point. A red goes to the owning lane as a ticket (IR/codegen → A,
dialect → P, NilPy → N, RTL → B). **T must never adjust an expectation to make a red test
pass** — that is option 1 arriving through the back door.

**Collision note:** wiring means editing the **Makefile**, which is NOT in T's file list
(`testmgr.py`, `twatch.py`, `tstate/**`, the fuzzers) and is shared with A. T should
announce the batch rather than sprinkling Makefile edits across days.

**Judgement note:** deciding what a *Pascal* test should assert when its commit does not
say needs dialect knowledge, not test-infra knowledge. T should park those with a note
rather than guess, keeping the batch mechanical and honest.

## Re-filed as work

See `chore-a-sweep-the-unwired-tests-into-the-suite` (Track A).
