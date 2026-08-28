---
slug: bug-t-nothing-exercises-o3-so-its-clean-record-is-empty
title: "Nothing in the matrix runs -O3, so \"no failures at -O3\" cannot be distinguished from \"nobody ran -O3\""
track: T
prio: 50
type: bug
status: backlog
found: 2026-08-28
found-by: frank-optimize-b4 (fell out of the W2 promotion question); filed by the coordinator
blocked-by: []
summary: "New optimisation passes land behind -O3 because nothing gates OptLevel>=3 — which is exactly why nothing EXERCISES it. The tier has no failures because it has no runs, and those two states are indistinguishable in every report we keep. Any -O3 to -O2 promotion is therefore a first exposure wearing a promotion's clothes."
---

# Nothing exercises `-O3`, so its clean record is empty

Filed 2026-08-28 by the coordinator, out of frank-optimize-b4's question about
promoting the W1/W2 slices from `-O3` to `-O2`. **Track T owns tier composition;
Track O found the gap and does not fix it here.**

## The two halves that compose badly

CLAUDE.md's Track O rule: *"New passes land behind `-O3` (a free tier — nothing
gates `OptLevel>=3` yet) and promote to `-O2` per-pass only after the full gate;
`-O2` stays the proven default."*

The tier is free **because nothing gates it**. But the same sentence, read as an
instrument rather than as a policy, says: nothing *runs* it either.

> **"No failures at `-O3`" cannot be distinguished from "nobody ran `-O3`."**

Both produce an empty red list, in every report we keep. This is the same shape as
`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good` — a skip and a
pass being indistinguishable — one level up, in tier composition rather than in the
ledger.

## Why it matters now rather than in principle

The `-O3` tier is where every new optimisation pass lives before promotion. The
promotion criterion is "after the full gate" — but the full gate does not compile
anything at `-O3`, so passing it says nothing about the pass being promoted.

**A promotion from `-O3` to `-O2` today moves a pass from an unobserved tier
straight to the proven default.** That is not a promotion, it is a first exposure
wearing a promotion's clothes. The coordinator deferred the W2 promotion on exactly
this ground.

The risk is not hypothetical for this campaign: frank-optimize-b4's first W2 build
**silently refused the hottest shape in the language** (it guarded on IR node types,
and a for loop's own increment carries `tyUnknown`, so it fired on `s := s + j` and
not on `i := i + 1`). Every output stayed byte-identical and every test stayed green,
because **a missing optimisation is not a wrong answer and no correctness suite can
see one.** Only disassembly caught it. A tier nobody runs cannot catch even the
cases that *do* change behaviour.

## What would close this

Not prescribed — T owns the design. The seed already exists: frank-optimize-b4's
`w2stress.pas` drives all five ops in-place at every integer width past their wrap
points, signed/unsigned narrowing, `{$Q+}`, `try`/`except`, var and value params and
pointer arithmetic, and **compares `-O0`/`-O1`/`-O2`/`-O3` output for agreement**.
That is the shape the matrix is missing: a differential across optimisation levels,
where the oracle is the lower level rather than a recorded expectation.

Open questions for whoever takes it: whether `-O3` belongs in the quick tier at all
(it lengthens the step every lane is on), or only in limited/full; and whether
per-level differential is cheaper as a handful of dense stress programs than as a
re-run of the corpus.

## Not blocked, and not urgent today

Nothing is waiting on this right now — the promotion it gates has been deferred, so
p50 is honest rather than parked. **It becomes blocking the moment anyone proposes
promoting a pass to `-O2`**, and whoever proposes that should be pointed here first.
