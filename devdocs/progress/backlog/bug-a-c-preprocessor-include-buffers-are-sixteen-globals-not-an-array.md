---
prio: 40
track: A
type: refactor
blocked-by: []
summary: "The C preprocessor's include buffers are sixteen separate AnsiString globals in defs.inc, dispatched by two hand-written `case depth of 0..15` ladders in cpreproc.inc. That is one datum wearing sixteen names, it caps include nesting at 16, and until 2026-08-30 the missing `else` on the length ladder returned an UNASSIGNED function Result past the end. The undefined read and the dishonest guard are fixed; making it an array is what actually raises the limit, and the storage is Track A."
status: new
owner: ""
---

# `CPrepInclude0..15` should be an array

## What exists

`compiler/defs.inc:3616`:

```pascal
  CPrepInclude0 : AnsiString;
  CPrepInclude1 : AnsiString;
  ...
  CPrepInclude15: AnsiString;
```

and in `compiler/cpreproc.inc`, two ladders that exist only to index them:

```pascal
procedure CPLoadInclude(depth: Integer);
begin
  case depth of
    0: LoadFile(CPrepPath, CPrepInclude0);
    ...
    15: LoadFile(CPrepPath, CPrepInclude15);
  end;
end;

function CPIncludeLength(depth: Integer): Integer;   { the same sixteen, again }
```

Plus a third `case` in `CPProcessInclude`. Three ladders, sixteen arms each,
all saying "the buffer at `depth`".

## What has already been fixed, so this ticket is not urgent

`bug-c-an-include-nested-deeper-than-16-is-silently-dropped` (frankC,
2026-08-30) closed the dangerous half **within Track C's files**:

- `CPIncludeLength` fell off the end of its `case` with `Result` never
  assigned, and the include search read that. Now `else Result := 0`.
- `CPInclude` guarded on `MAX_CPREP_INCLUDES = 128` while the table holds
  sixteen, so depths 16..127 reached a load that did nothing. It now refuses at
  the real limit with a message naming it.

So the silent wrong value is gone: 18-deep nesting used to print `0` where gcc
prints `17`, and now reports *"C include nesting too deep (the preprocessor has
16 include buffers; this include is at level 17)"*.

## What is left, and why it is worth doing anyway

**The limit is still 16, and it is close.** A model of the recursion over this
box's real header sets — deliberately over-estimating, since it counts
`#include`s inside conditional blocks the preprocessor skips — puts
`gtk/gtk.h`, the deepest set this repo compiles against, at **15**. One level.
Nothing hits the ceiling today and the failure is now loud rather than silent,
but the margin is a single header.

**And this is a textbook `normalise-dont-special-case` case.** Sixteen globals
and three parallel ladders are one datum wearing sixteen names; the missing
`else` was exactly the kind of defect a second (third) copy of a dispatch
harbours, and it went unnoticed for as long as the arms happened to agree. An
array deletes all three ladders and makes the limit one constant.

## Shape

`CPrepInclude: array[0..MAX_CPREP_INCLUDES-1] of AnsiString` in `defs.inc`,
with the three `case` ladders in `cpreproc.inc` collapsing to `CPrepInclude[depth]`.
Then `MAX_CPREP_INCLUDES` becomes the *true* limit and the extra guard added by
the ticket above can be deleted — it is deliberately the only line that needs
removing.

Watch the memory: sixteen AnsiStrings is nothing, 128 is still nothing, but
these hold whole preprocessed files and the array is global, so they are never
freed. If that matters, size the array to a real limit rather than to 128.

## What a fix must assert

- 16-deep nesting still compiles and gives gcc's values (already a test).
- Whatever the new limit is, one past it is the *nesting* diagnostic, not a
  dropped header (already a test; update the depth).
- A depth between 17 and the new limit now WORKS, which is the point.
- Self-host fixedpoint, and the gtk set — Pascal programs binding C headers
  reach this code hardest.

## Log
- 2026-08-30 — filed by frankC. The C-lane half (undefined read, honest guard,
  both tests) landed first; this is the storage change, which is Track A's.
