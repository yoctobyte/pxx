---
track: P
prio: 35
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
found-by: frankB
summary: "`function WordPosition(const N: Integer; ...): Integer; var i, n, count: Integer;` declares a parameter `N` and a local `n` in one routine. Pascal is case-insensitive, so that is ONE identifier declared twice and fpc refuses it as a duplicate; pxx accepts it silently and registers two symbols. Three routines in our own `lib/rtl/strutils.pas` were written that way and read the two as different variables. Found only because a name-resolution fix (bug-p-an-exact-case-match-in-an-outer-scope-beats-a-case-insensitive-one-in-a-nearer-scope) made the two collapse onto one symbol and broke them -- the duplicate itself is invisible today. THE VALUE IS THE DECLARATION-SITE DIAGNOSTIC: the collision is trivially detectable where it is written and is otherwise found three functions later as a wrong value. Not landed with the resolution fix because a refusal is a NARROWING over a population nobody has enumerated, and that commit already moved name resolution."
---

# A parameter and a local that differ only in case are two symbols

Measured 2026-09-06 at compiler `6a676f92b94d`.

```pascal
function WordPosition(const N: Integer; const S: AnsiString;
                      const WordDelims: TSysCharSet): Integer;
var i, n, count: Integer;
begin
  n := Length(S);
  while (i <= n) and (count <> N) do ...        { `n` and `N` are ONE identifier }
```

fpc 3.2.2 refuses this (`Duplicate identifier`). pxx registers two symbols and,
until the resolution fix above, kept them apart by case — so the routine
*worked*, and would have started returning wrong answers the moment the lookup
was corrected. Three routines in `lib/rtl/strutils.pas` had this shape
(`WordPosition`, `ExtractWordPos`, `ExtractDelimited`); the locals were renamed
to `sLen` as part of that fix.

## Why it is worth a diagnostic rather than a rename campaign

The collision is decidable **at the declaration**, from two lists we already
have, and it is otherwise found as a wrong value in a routine that reads the two
names as different variables. Everything about this defect is cheap on one side
of the line and expensive on the other.

## Why it was not landed together with the resolution fix

A refusal is a narrowing, and the population is unknown: no sweep has asked how
many routines across `lib/**`, `compiler/**`, the corpus and the frontends
declare a parameter and a local differing only in case. Two were found by
accident, in one file, because a *different* change made them fail. **The first
step is the census, not the diagnostic** — and if the count is large, the answer
may be a warning rather than an error.

## Boundary, so nobody re-derives it

Two LOCALS differing only in case, or two PARAMETERS, are the same question and
should be caught by the same check. A local differing in case from a symbol in an
OUTER scope is NOT this: that is ordinary shadowing and is now resolved
correctly.

## Neighbour

[[bug-p-an-exact-case-match-in-an-outer-scope-beats-a-case-insensitive-one-in-a-nearer-scope]]
is the lookup half; this is the declaration half, and only the declaration half
can name the file that is wrong.
