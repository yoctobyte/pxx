---
slug: chore-t-nothing-in-the-matrix-runs-o3-so-no-failures-is-unfalsifiable
title: "Nothing in the test matrix compiles at -O3, so \"no -O3 failures\" cannot be distinguished from \"nobody ran -O3\""
track: T
prio: 60
type: chore
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-28
summary: "The -O3 tier is free because nothing gates OptLevel>=3 — but that also means nothing EXERCISES it. Every -O3 pass in the register-pressure campaign has been validated only by its author's own bench. Promoting one to -O2 would move it from an unobserved tier to the proven default in one step. Same shape as the skip-counted-as-pass bug fixed 2026-08-28, one level up in tier composition. Asks for an optimisation-agreement job: compile a fixed set at -O0/-O1/-O2/-O3 and require all four outputs to agree. Filed by Track O, which found the gap; T owns tier composition."
---

# The gap

CLAUDE.md's Track O rule is that new passes *"land behind `-O3` (a free tier —
nothing gates `OptLevel>=3` yet) and promote to `-O2` per-pass only after the
full gate."* The first half is true and is exactly why `-O3` is the right place
to land experimental codegen.

**The second half has no evidence behind it, because the same sentence explains
why: nothing gates `OptLevel>=3`. Nothing gating it also means nothing
exercising it.**

So today:

- `testmgr` tiers compile at the default `-O`. No job passes `-O3`.
- Therefore the matrix has never reported an `-O3` failure — and it never could,
  for any pass, however broken.
- **"No `-O3` failures" and "nobody ran `-O3`" produce byte-identical evidence.**

That is the same shape as the skip-counted-as-pass bug Track T fixed on
2026-08-28, one level up: there a skipped job was scored as a passing one; here
an unexercised *tier* reads as a clean one. In both cases the absence of a
signal is being read as a negative result.

# Why this blocks a real decision, not a hypothetical one

`feature-opt-o3-register-pressure` has landed four `-O3` passes
(`562965e1c`, `46c8cf47e`, `c93292fe4`, and item 1), and the campaign's next
step is the `-O2` promotion experiment. **Promoting a pass from `-O3` to `-O2`
today moves it from an unobserved tier to the proven default in one step, with
no evidence behind it beyond the author's own benchmark.** That is a first
exposure wearing a promotion's clothes.

The passes are not suspected of being wrong — each was gated on the self-host
fixedpoint, a hand-written differential, and a cross-target hash comparison.
The point is narrower and worse: **those are all the author's own checks.** The
matrix has independently observed none of them, so promotion has nothing to
appeal to but the same evidence that justified landing.

# What is being asked for

An **optimisation-agreement job**: compile a fixed program set at `-O0`, `-O1`,
`-O2` and `-O3`, run all four, and require the outputs to agree. Any
disagreement is a codegen bug in whichever level is the odd one out, and it
needs no recorded expectation — the other three levels are the oracle. That
property is what makes this cheap: **no expected-output files to maintain**, and
it stays correct as the programs change.

Rough shape, for T to size and place — not a design handed down:

- Cheapest useful version is one job over the existing test corpus.
- Cost is ~4x compile + 4x run of whatever set it covers, so it likely belongs
  in `limited`/`full` rather than `quick`.
- Worth extending to the cross-targets that can execute; `-O3` is x86-64 and
  aarch64 only per Track O's per-backend rule, so the other four only need to
  *compile* at every level, not run.

# A seed that already exists

`w2stress.pas` (written for `c93292fe4`, in the W2 scratchpad — ask Track O for
it, or regenerate from the ticket) is the shape of the input this wants: all
five in-place ALU ops at every integer width driven past its wrap point, signed
and unsigned narrowing, self-referencing assignment, non-commutative `x := x - y`,
`{$Q+}`, in-place stores inside `try/except`, `var` and value params, pointer
arithmetic. It is deliberately dense in the constructs residency and the operand
scheduler transform.

Its `-O0/-O1/-O2/-O3` comparison is precisely the check this ticket wants run by
the matrix instead of by hand.

**One trap it carries, and any FPC-oracled version of this job must know it:**
under `{$Q+}` pxx detects a LongInt overflow that `fpc -O2` misses, so the FPC
oracle *disagrees by design* on that case and a differential harness scores it
as our failure. Recorded in `devdocs/dev/pascal-dialect-divergences.md`. The
four-level agreement check does not have this problem, because it needs no
external oracle at all — which is another reason to prefer it.

# Boundaries

- **Filed by Track O, to be done by Track T.** O found the gap; tier composition
  and the report format are T's tool, and T owns the tool. This is not a request
  for T to fix a compiler bug — there is no compiler bug here.
- **Not a blocker on landing more `-O3` passes.** `-O3` remains free and
  experimental; that is the tier's purpose and it is working as intended.
- **It IS a precondition on `-O3` -> `-O2` promotion**, per the coordinator
  (2026-08-28). Once `-O3` is genuinely swept, promotion becomes a decision with
  data under it.
