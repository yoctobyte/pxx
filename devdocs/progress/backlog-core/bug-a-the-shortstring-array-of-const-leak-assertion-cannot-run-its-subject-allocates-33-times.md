---
slug: bug-a-the-shortstring-array-of-const-leak-assertion-cannot-run-its-subject-allocates-33-times
track: A
prio: 50
type: bug
blocked-by: []
status: backlog
found: 2026-09-05
found-by: frankC
owner: unassigned
summary: "The heavy gate is RED at HEAD on a row nobody's change touched: test-core's `tools/assert_no_leak.sh test_ssvarrec26 200` on test_shortstring_in_array_of_const.pas refuses with `only 33 allocations — too few to show anything` and exits 1, failing Makefile:11159. assert_no_leak declines below 100 allocations because a run that allocated almost nothing cannot demonstrate the absence of a per-iteration leak. The GUARD is right; the SUBJECT is the problem — the program does a single pass, not a loop, so it can never reach the floor whatever the compiler does. Either the test needs an iteration count or the row needs a different assertion class."
---

# The ShortString array-of-const leak assertion cannot run — its subject allocates 33 times

## Symptom

```
tools/assert_no_leak.sh test_ssvarrec26 200 .../test_ssvarrec_census26
assert_no_leak[test_ssvarrec26]: only 33 allocations — too few to show anything.
  pxx-census: allocs=33 frees=13 live=20 bytes=1328 reuse=12 list=0 bump=21 arenas=1
make: *** [Makefile:11159: test-core] Error 1
```

`tools/assert_no_leak.sh:55` refuses when `allocs < 100`, with the comment
*"A run that allocated almost nothing cannot demonstrate the absence of a
per-iteration leak either: the subject has to have run."* That guard is
correct, and it is exactly the precondition-assertion discipline CLAUDE.md
asks for. The subject is what is wrong: the row asks for 200 iterations and
the program performs a single pass, so it cannot reach the floor no matter
what the compiler does.

## It is NOT anyone's in-flight change

Measured by ablation while landing an unrelated aarch64/arm32 backend fix
(binary `5c72f8297ee1`): stash the change, rebuild — `converged after 1
round(s)`, binary `80a3f9e73673` — and the census is **identical**,
`allocs=33 frees=13 live=20 bytes=1328`, still exit 1. Restoring the change
rebuilt back to `5c72f8297ee1`, the same sha as before the ablation, which is
also a determinism check on the two rebuilds.

The two files that fix touches are `ir_codegen_aarch64.inc` and
`ir_codegen_arm32.inc`, neither of which a native x86-64 compile reaches, so
the ablation confirmed a structural argument rather than testing a live
hypothesis — but the number is the number, and "no observable difference" is a
claim about one target, so it was worth the two minutes.

## Where it came from

The row arrived with `1cac1742a` *"fix(A): a ShortString in `array of const`
boxed a pointer nobody could use"*, whose Makefile comment says the fix parks
each ShortString element in an owning hidden AnsiString local — *"exactly the
shape that leaks if the handle never gets an owner. A value assertion CANNOT
see that."* The reasoning for wanting a leak assertion here is right, and it
is the same reasoning `assert_no_leak` exists for. The assertion simply never
got a subject that could satisfy it.

## Fix

Either give `test_shortstring_in_array_of_const.pas` a loop around the
`array of const` calls so the census has something to count — the shape every
other `assert_no_leak` subject already has — or drop the row to an assertion
class the single-pass program can satisfy, and say which in the Makefile
comment.

**Do not "fix" it by lowering assert_no_leak's floor.** The floor is what makes
it a guard rather than a row that prints PASS, and it is shared by every other
leak subject in the suite.

## Cost

The heavy gate mode is RED for every lane until this lands, so anyone who runs
the wide suite their change genuinely warrants gets a red that is not theirs
and has to spend an ablation to discover that. The quick tier is unaffected,
and so is `make compiler/pascal26`.
