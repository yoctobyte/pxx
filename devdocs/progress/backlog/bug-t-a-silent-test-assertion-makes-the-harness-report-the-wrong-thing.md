---
track: A+T
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

---

## Adjacent instance, 2026-08-28 — an assertion that could not fail at all

Added by Track T on the coordinator's ask, with the relationship stated
precisely rather than assumed, because the two are **not the same mechanism**:

| | this ticket | the instance below |
| --- | --- | --- |
| the assertion | **fails silently** | **never fails** |
| what you see | a red job with a wrong reason | a green suite |
| what it costs | hours chasing the wrong lead | a defect ships |

The fix proposed above — a helper that prints both operands on mismatch — does
**not** address the instance below, because there is no mismatch to print. They
belong to one family (*an assertion that does not assert what it appears to*)
and want two different fixes. Recorded here so the family has one place, not
because one fix covers both.

### The instance

While landing
[[bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good]]
(`0dec0194a`), a guard asserted that an execution check ran *before* the
tier-coverage fallback in `range_for()`:

```python
assert body.index("job_anchor") < body.index("parent_ran_job")
```

`job_anchor` also appears in the **block comment above the call**. So
`body.index("job_anchor")` found the *prose*, not the call, and the assertion
passed no matter where the call actually sat. Deliberately moving
`parent_ran_job` above the call — restoring the original bug with the fix still
visibly present in the file — fired **zero of twelve** guards.

It is now anchored on the expression:

```python
call = body.index("aname, why = job_anchor(st, name)")
assert call < body.index("parent_ran_job")
```

### The rule, and the reason it survived a careful read

> **An assertion that matches TEXT can be satisfied by PROSE.** Anchor a guard
> on the expression, never on a name that also appears in a comment.

This applies to every source-inspecting guard in `tools/*devtest*.py`, of which
there are now several — including three added the same night, in the ticket that
found this. Those inspect source precisely because the property under test is
structural (ordering, which predicate a statement uses, whether a warning
precedes a signal), and a structural property is exactly the kind a substring
can appear to satisfy.

**It was found by running a mutation, not by reading the test.** That is the
transferable half: reading a test to check whether it can fail draws on the
same understanding that wrote it, so it shares the test's blind spots by
construction. Breaking the code and watching which guard fires does not.

The four mutations run against that ticket, and what each caught:

| break | guards fired |
| --- | --- |
| drop the skip branch (the original bug) | 2 |
| `PASSLIKE = ("pass",)` (the mirror image) | 4 |
| map advances on `PASSLIKE` (bug one level deeper) | 1 |
| **call moved below the coverage path** | **0 → 1 after the fix** |

The one that caught nothing is the one where the fix is still in the file and
merely unreachable — the variant least likely to be noticed in review.

---

## 2026-08-29 — STEP 1 IS DONE AND NAMED. What remains is a Track A dispatch.

`tools/expect_same.sh` exists, with 11 guards in `tools/expect_same_devtest.py`
and four mutations proving they fire. Filed and closed as its own ticket —
[[feature-t-expect-same-a-recipe-assertion-that-prints-its-mismatch]] — rather
than as step 1 of this one, so this ticket does not read as half-built work.
The reasoning is worth keeping: **a parent with step 1 landed and 480
conversions outstanding is worse than an untouched one for whoever inherits
it**, because "in progress" hides that nobody is on it.

```
tools/expect_same.sh <label> <actual> <expected>
```

Exit 0 in silence on equality; on mismatch a labelled unified diff of both
operands, exit 1. So a converted recipe line reads:

```make
	tools/expect_same.sh aarch64-fima "$$(tools/run_target.sh aarch64 $(TESTTMP)/x)" "$$($(TESTTMP)/x_x64)"
```

Four properties beyond "it diffs", each guarded, because the reason field is the
deliverable and not the diff: the **label** is in the output (the tail must say
which assertion spoke); `-` is **expected** and `+` is **actual** (pinned, since
transposition is its own wasted hour); **no absolute `/tmp` path** (testmgr
rewrites those, so a leaked one varies by construction); and the text is
**byte-stable across runs** (`diff -u` stamps mtimes on its header lines, and a
reason that changes every run reads as a *new* failure to anything comparing
this run's reds against the last).

One deliberate non-change: two empty operands still **pass**, because 480 call
sites is the wrong place to alter pass/fail semantics — but a warning naming the
label now goes to stderr, so a vacuous pass is at least visible.

### What is left: exactly the mechanical conversion this ticket describes

Unchanged in shape from the plan above — convert the **480 cross-target**
assertions first (highest damage, one shape, mechanical), leave the other ~1,981
until one or two have proven themselves. That work edits `Makefile`, so it
carries **Track A's file ownership and gate**, and per this ticket's own Gate
section must not land concurrently with other A edits to `Makefile`.

Nothing here is blocked any more. The helper is a dependency that now exists.

## Retracked `T` → `A+T` by the coordinator, 2026-08-29

**This is a dispatch call, made rather than left implicit.** pxx-a5 flagged that
`next --track T` headed with this ticket and **no T agent can take it** — its
remaining half edits `Makefile`, Track A's file-lane. It declined to retrack,
correctly: retracking *is* the dispatch call and that call is mine.

**Why `A+T` and not plain `A`.** CLAUDE.md's two axes settle it: **A is the
file-lane** (Makefile — who owns this file when two agents run at once) and **T is
the work-tag** (test diagnostics — what kind of work this is). Exactly the shape of
`A+O`, `A+S`, `B+F`. Dropping the `T` would lose what the ticket is *about*;
keeping only `T` puts it in a queue whose agents cannot act on it.

> **A queue head that its own lane cannot work is worse than an empty queue** — it
> occupies the ranker's top slot and every `next --track T` re-offers it, so the
> lane reads as busy while nothing is takeable.

**Step 1 is DONE and this is now a clean Track A dispatch:** `tools/expect_same.sh`
landed (`b194ef7ec`) as its own closed unit — labelled output, `-` expected / `+`
actual pinned by a guard, no absolute `/tmp` path (testmgr rewrites those), and
**byte-stable across runs** because `diff -u` stamps mtimes on its header lines and
a reason that changes every run reads as a NEW failure to anything comparing this
run's reds against the last.

What remains is **480 mechanical conversions in `Makefile`**, against a helper that
exists and is guarded, **nothing blocked**. The gate constraint stands: it must not
land concurrently with other Track A edits to `Makefile`.

## 2026-08-29 — batch 1 landed: 474 converted. And the "480" was never 480.

Dispatched to Track A+T. Before converting anything I censused the recipe lines
rather than trusting the figure this ticket has carried since 2026-08-26, because
the figure is what sets the scope. It has drifted, and more importantly it was
always a **single number over six different shapes**:

| shape | count | convertible? |
| --- | --- | --- |
| clean output-compare, `test "$$(run_target ARCH $(TESTTMP)/BIN)" = "EXP"` | **474** | yes — **converted, this commit** |
| exit-status check, `test "$$?" = "143"` | 37 | **no — see below** |
| piped-stdin compare, `printf … \| tools/run_target.sh …` | 35 | yes, different regex — batch 2 |
| in-loop (trailing `\` inside `for arch in …`) | 13 | yes, different shape — batch 3 |
| other test shapes | 9 | case by case |
| bare run, no assertion at all | 9 | nothing to convert |
| **total `run_target.sh` recipe lines** | **547** | |

**The 37 exit-status checks are not convertible and must not be made to look
converted.** `expect_same.sh` compares two strings; `test "$$?" = "143"` asserts a
*signal*. Wrapping it would be a semantic change wearing a mechanical diff's
clothes — precisely the failure this ticket is about, since the result would read
as covered while asserting something else. They keep their silence and are listed
here so the next reader knows it was a decision, not an oversight.

### What batch 1 actually did

One line changed per hunk; nothing else in any recipe was touched, so the diff is
474 independent 1↔1 hunks and stays reviewable.

```make
-	test "$$(tools/run_target.sh i386 $(TESTTMP)/test_i386_hello)" = "Hello"
+	tools/expect_same.sh i386/test_i386_hello "$$(tools/run_target.sh i386 $(TESTTMP)/test_i386_hello)" "Hello"
```

Label is `ARCH/BIN`. Across all 474 that is **unique — zero collisions** — which
is what makes the label worth having: a tstate reason line now names the job.

### Verified by count and by construction, not by the suite going green

The suite going green would prove nothing here: these assertions *already* pass.
A conversion that silently dropped an assertion would also be green. So:

- 474 lines changed, file length unchanged (15424 → 15424).
- Every diff hunk changes exactly one line (checked with `git diff -U0` on the
  hunk headers; zero hunks with a count ≠ 1).
- For all 474: leading tab/`@`/`-` prefix, the **actual** operand, and the
  **expected** operand are byte-identical to the originals, and the label equals
  `ARCH/BIN` from that same line. Zero drift.
- All 474 rewritten lines parse as shell (`bash -n` over the extracted set, with
  `$$`→`$` and `$(TESTTMP)`→`/tmp`), and `make` parses the Makefile.
- `expect_same.sh` exercised live on both arms: silent exit 0 on match, exit 1
  with a `diff -u` naming the label on mismatch.

The first check is the one that matters: it is the difference between "the
transformation applied" and "the file still builds".

### Remaining

Batches 2 (35 piped-stdin) and 3 (13 in-loop) are still bare `test`. They are
different regexes and land separately, for the same reason batch 1 kept one
assertion per hunk.

## 2026-08-29 — batches 2 and 3: 498 converted. The census corrected itself again.

Batch 1's shape table was itself too coarse, and converting exposed it. The
"35 piped-stdin" and "9 other" buckets were not two shapes — they were one
regex's worth of standalone compares (14) plus in-loop lines double-counted from
the backslash bucket. **The real terminal figures, and these are measured after
the conversion rather than predicted before it:**

| shape | count | outcome |
| --- | --- | --- |
| clean output-compare | 474 | converted (batch 1) |
| standalone compare, pipes/`printf` on either side | 14 | converted (batch 2) |
| in-loop compare (`for arch in …`, trailing `\`) | 10 | converted (batch 3) |
| **total converted** | **498** | |
| exit-status check, `test "$$?" = "N"` | 37 | **not convertible — by decision** |
| in-loop non-assertions (a capture, a redirect, an `if`) | 3 | nothing to compare |
| bare run, no assertion at all | 9 | nothing to compare |

That the number moved twice under measurement is the point of the row about the
480: **a count over heterogeneous shapes is a guess wearing a number's clothes**,
and the only thing that ever settles it is doing the transformation and counting
what is left.

### The 37 that stay silent, and why that is finished work

`test "$$?" = "143"` asserts a **signal**. `expect_same.sh` compares two strings.
Wrapping them would produce a diff that looks exactly like the other 498 while
asserting something different — a semantic change in a mechanical diff's
clothing, landing in a review too large to catch it. They keep their silence, and
they are listed here so the next reader knows this was decided and measured, not
skipped. If they ever need a diagnostic it wants a *different* helper, one that
compares exit statuses and says so.

### Batch 3's shape, which is not batch 1's

In-loop lines carry a trailing `\` and sometimes a `|| { echo …; exit 1; }`
trailer — and in one case (`Makefile:4200`) the `||` is on the *following*
continuation line, so it guards the converted command exactly as it guarded the
`test`. Every trailer was preserved verbatim; none were tidied, even the four
whose `echo "cross … FAIL on $$arch"` is now partly redundant with
`expect_same.sh`'s own output. Tidying them would be a second thing per hunk.

Labels here interpolate: `$$arch/lib_net_$$arch` resolves at run time, so the
failing job names its own architecture without the recipe being unrolled.

Verified as batch 1 was — 14 and 10 changed lines, every hunk 1↔1, prefix,
operands and trailer byte-identical, file length unchanged, zero label collisions
against the 474 — plus, because a loop fragment cannot be parsed alone, the two
enclosing **recipe blocks** were reassembled, make-expanded and passed through
`bash -n` whole, with a check that all 10 changed lines fell inside a block that
was actually checked. `make` parses the file and the self-host fixedpoint builds.
