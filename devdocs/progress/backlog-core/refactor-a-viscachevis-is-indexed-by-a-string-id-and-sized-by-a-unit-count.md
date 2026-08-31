---
track: A
prio: 45
type: refactor
blocked-by: []
summary: "VisCacheVis is subscripted by a Strs[] index but sized by MAX_UNITS, a unit COUNT. The two are unrelated quantities, so the array's bound has no relationship to the values that index it. Three range checks now stand between that mismatch and memory corruption; one of them was missing and cost a multi-session bug (bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream). Separate the domains so the checks are belt-and-braces rather than load-bearing."
status: backlog
owner: unassigned
---

# VisCacheVis is indexed by a string id and sized by a unit count

Follow-up to [[bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream]],
which is FIXED — this is the class behind that instance, split out deliberately
rather than bundled into a fix that needed to land.

## The mismatch

`VisibilityAllows` (`compiler/symtab.inc`) memoizes into

```pascal
VisCacheVis : array[0..MAX_UNITS] of Boolean;   { MAX_UNITS = 256 }
```

and subscripts it with `curUnit + 1`, `declUnit + 1`, `UsesEdgeTo[i] + 1`. Those
are **`Strs[]` indices** — the function's own header says *"Strs[] indices offset
by 1 so curUnit = -1 (the main program) indexes slot 0"* — while `MAX_UNITS` is a
count of compiled units.

**Nothing relates the two.** `CompiledUnitCount` is genuinely capped at 256, so
it is tempting (and a comment in the file did exactly this) to conclude the
subscripts cannot exceed the bound. They can, trivially: a unit whose *name*
interns past string slot 255 overflows, and which names intern where depends on
the order the `uses` graph was walked.

## Why it is worth a ticket rather than a comment

The array is followed in `defs.inc` by `WarnIgnoredDirectives`, `PreScanPass`,
`GenericMethodBuffered`. An overflow writes `True` into compiler control flags —
silent, order-dependent, and it presents as a *parse* error in an unrelated file.
It cost two sessions and two wrong framings before anyone looked at the array.

Three range checks are what currently stand between the mismatch and that
corruption, and they are load-bearing: one was missing, and its absence was the
bug. A design where forgetting a check cannot corrupt memory is worth more than
a fourth correct check.

## Options

1. **Size the cache by the string table** (`MAX_STRS`-derived). Simplest; costs
   memory on a hot global, and re-couples to a different cap.
2. **Key on a real unit ordinal** — resolve the string id to a `CompiledUnits`
   slot and index by that. Restores the meaning `MAX_UNITS` implies, but adds a
   lookup to a function called from *every* routine, class, type and symbol
   resolution, which is precisely why the memo exists.
3. **Keep the checks, make them structural** — one accessor that clamps, so no
   call site can subscript raw.

Recommendation: **(3) first** because it is cheap and removes the class, then
(2) if profiling says the ordinal lookup is affordable.

## Care

`VisibilityAllows` is called from every symbol lookup; the memo is there because
a clear-plus-scan per query is quadratic in the edge table. Any change needs the
self-host fixedpoint plus a timing check, not just correctness.
