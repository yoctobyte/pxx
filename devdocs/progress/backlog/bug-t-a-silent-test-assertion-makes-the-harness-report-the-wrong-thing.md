---
track: T
prio: 45
type: bug
blocked-by: []
summary: "2461 Makefile assertions are a bare `test \"$$(...)\" = \"...\"`, which prints NOTHING when it fails. job_reason() is the log tail by deliberate design, so for those jobs the reason it records is whatever the recipe printed just before — and for the 480 cross-target ones that is two compile summaries with different code sizes, which reads exactly like a codegen divergence. It misled a Track T session for hours. The repo already uses `diff -u` in 362 places; the good pattern exists and is not reached. Fix edits Makefile, which is Track A's file-lane."
---

# A silent `test` assertion makes the harness report something else, confidently

- **Track T** (test diagnostics / report format) — **but the fix edits
  `Makefile`, which is Track A's file-lane.** Filed here because the subject is
  what a red job tells you; landing it needs A, or A's go-ahead.
- Found 2026-08-26 while triaging
  [[bug-t-a-blame-range-is-computed-from-what-changed-not-from-what-the-job-can-see]]'s
  live aarch64 entry.

## What it looks like from the outside

`test-aarch64#src:test/test_forin_member_access.pas` went red and tstate
recorded, as the reason:

```
ok: $TMP  [code=152328B  data=3040B  bss=42368B  procs=130] | ok: $TMP  [code=65652B  data=3088B  bss=42504B  procs=130]
```

Two builds of one source, one at 152 KB and one at 65 KB, presented as the
reason an aarch64 test failed. **That reads as an aarch64 codegen divergence and
it is not one** — they are simply the aarch64 and the x86-64 build of the same
program, and two targets emitting different amounts of code is the null
hypothesis, not a finding. A Track T session read them as a divergence, said so
to a peer, and had to retract it.

## Why the harness said that

`job_reason()` records the **log tail**, deliberately and with a good argument:

> Deliberately the log TAIL rather than a pattern match: a signature list goes
> stale silently and then reports nothing for the failure shapes it has not met
> yet […] What the job printed last is true for every shape, including the ones
> nobody has seen.

That reasoning is sound and should not change. The defect is upstream. The
recipe is:

```make
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_forin_member_access.pas $(TESTTMP)/test_aarch64_fima
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_forin_member_access.pas $(TESTTMP)/test_aarch64_fima_x64
	test "$$(tools/run_target.sh aarch64 $(TESTTMP)/test_aarch64_fima)" = "$$($(TESTTMP)/test_aarch64_fima_x64)"
```

`test` **prints nothing when it fails.** It captures both operands, compares
them, discards both, and exits 1. So the last thing in the log is always the two
compile lines, and a faithful tail-recorder faithfully records them.

**A silent assertion does not merely fail to explain itself — it makes
everything downstream explain something else.** That is worse than an empty
reason field, which at least reads as "unknown": `job_reason()`'s docstring is
careful that an empty return "is never a claim that the job failed for no
reason", and this path defeats that care by handing it something to say.

## Scale, and the part that makes it a bug rather than a style note

| | count |
| --- | --- |
| recipe lines in `Makefile` | 13,214 |
| bare `test "$$(…)" = "…"` assertions | **2,461** |
| …of which cross-target (`run_target.sh` on both sides) | **480** |
| recipes that already `diff -u` and show the mismatch | **362** |

**The good pattern is already in this repo, 362 times.** `diff -u
test/x.expected -` prints the mismatch, so the tail *is* the failure. This is
the same shape as the rest of this ticket family — the right answer exists on
one path and the common path cannot reach it — except here it is not a missing
branch, it is 2,461 recipe lines written before anyone read a red from the
outside.

The 480 cross-target ones are the worst subset by a distance, because their two
preceding lines are *two compile summaries that differ*, which is the most
convincing wrong answer the log could possibly offer.

## Shape

1. **A helper in `tools/` (Track T's own lane), so the fix is one line per
   recipe.** Something like `tools/expect_same.sh <label> <actual> <expected>`:
   exits 0 on equality, and on mismatch prints a labelled unified diff of the
   two operands before exiting 1. Then a recipe line becomes
   `tools/expect_same.sh aarch64-fima "$$(...)" "$$(...)"`.
2. **Convert the 480 cross-target assertions first.** Highest damage, smallest
   set, and they share one shape so the conversion is mechanical.
3. Leave the other ~1,981 alone until 1–2 have proven themselves. Most compare
   against a literal, where the reason field is less actively misleading — it
   names the wrong lines but does not fabricate a plausible finding.

**Do not** solve this inside `job_reason()` by guessing whether the tail "looks
like a failure". That is a signature list wearing a different hat, it is exactly
what the docstring rejects, and it would go stale silently.

## What this is NOT

Not a compiler bug and not a cross-target bug. The aarch64 job that produced the
example passes 12/12 at HEAD; it was an unattributable flake
([[bug-t-a-blame-range-is-computed-from-what-changed-not-from-what-the-job-can-see]]).
The only defect here is that the harness described it wrongly, and would have
described any failure of those 480 jobs equally wrongly.

## Gate

Track T's tooling gate for the helper (`tools-devtest` green, with a guard that
the helper prints both operands on mismatch and is silent on equality). The
Makefile conversion carries **Track A's** file ownership and gate — self-host
fixedpoint plus the touched targets — and must not be landed concurrently with
other A edits to `Makefile`.

## Log
- 2026-08-26 — found while triaging the aarch64 red whose reason it corrupted;
  measured; filed. Nothing landed: the fix edits A's file-lane.
