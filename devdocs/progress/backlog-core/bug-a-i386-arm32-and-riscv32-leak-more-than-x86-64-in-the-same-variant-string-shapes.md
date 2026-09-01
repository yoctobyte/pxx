---
type: bug
track: A
prio: 4
summary: i386, arm32 and riscv32 leak MORE than x86-64 and aarch64 in the same variant/string shapes — 3616/3856/364 against 1549 on one program before the temp-ownership fix, and the allocation COUNT differs too (i386 8671 vs 5411), so at least one further scope-exit hole is target-specific
tags: [memory-leak, variant, ansistring, i386, arm32, riscv32, cross-target]
---

Fell out of
`bug-a-a-variant-converted-to-ansistring-leaks-whenever-the-result-is-a-temporary`
as a residual, and is deliberately NOT closed by it. Filed so the question has
an owner rather than sitting as a caveat in a test header.

## What was measured

`test/test_variant_string_temp_leaks.pas`, 400 trips over nine arms, `live` at
exit, before and after that fix:

| target | before | after |
| --- | --- | --- |
| x86-64 | 1549 | 2 |
| aarch64 | 1549 | 2 |
| i386 | 3616 | 1 |
| arm32 | 3856 | 2 |
| riscv32 | 364 | 1 |

**The fix cleared every target**, so nothing here is currently leaking and this
is not urgent. What it exposes is that the targets did not agree BEFORE it, and
they had no reason to disagree: the defect it fixed lives in shared IR, so all
five should have leaked the same amount. Two of them leaked more than twice as
much and one leaked a quarter as much.

The allocation COUNT differs too, which a leak alone does not explain: i386 and
riscv32 ran 8671 allocations before the fix and 6850 after, arm32 7707 -> 5411,
while x86-64 and aarch64 sat at 5411 both times. A pure ownership fix should not
move how many times the program allocates.

## Why it matters even though everything is green

The nearby release-matrix work
(`bug-a-scope-exit-release-matrix-has-four-holes-left-on-i386-and-arm32`) found
that i386 had no variant, promotable-int or record arm at all. These numbers are
consistent with more of that class still being present and currently MASKED —
masked because the arms in this program now balance, not because the holes were
filled. A masked hole reappears the moment a shape reaches it by another route.

## Where to start

Not from this program, which mixes nine arms. Split it: run each arm alone on
each target and find which arm produces the divergence. The arms are already
separate procedures. `riscv32` being LOW rather than high is the most
informative row — a target that leaks less than the shared-IR defect can explain
is either freeing something it should not, or not allocating something the
others do, and the allocation-count column says the second is in play.

Do not treat "all five are under the bound now" as an answer. That is the
condition under which this is cheap to investigate, not evidence there is
nothing there.

## Narrowed by a negative result (frankB, 2026-09-01) — NOT the general release matrix

frankB swept 20 shapes that measure clean on x86-64 across all five targets,
1000 trips each, at `42507851cdde`: interfaces (local, reassigned, function
result, in a dyn array, as a parameter), 2-D dyn arrays including shrink and
regrow, `for..in` over strings and over records, a class with a destructor,
`try/finally`, an open-array parameter, a concat loop, variant+promo in one
record, 3-deep nesting, inherited managed fields, and dyn-array-of-variant and
dyn-array-of-promo as record members.

**Every cell identical across x86-64 / i386 / arm32 / riscv32 / aarch64, and
every one clean (1 to 10).** No spread at all.

That matters because it removes the hypothesis this ticket was filed under. If
the scope-exit release matrix were broadly short on i386 and arm32, at least one
of twenty shapes covering interfaces, nested dyn arrays, destructors, `for..in`
and `finally` should have shown it. So the spread is specific to the variant
string-temp family rather than general to managed memory on those targets, and
the search should start there rather than in the release matrix.

**The harness was shown to reflect the target rather than falling back**, with a
positive instance rather than an assertion: a member-array run produced 12 on
i386 and riscv32 against 7 on x86-64 and aarch64 — a real 32-vs-64-bit split
from the promo stride. So the identical rows are identical because the counts
match, not because one binary ran five times. That is the check that makes a
20-shape zero mean something.
