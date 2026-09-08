---
slug: bug-p-a-bare-enclosing-function-name-read-in-a-nested-routine-recurses
title: "Reading the enclosing function's BARE name inside a nested routine is a recursive call here and the result VARIABLE in fpc"
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-07
summary: "Inside a NESTED routine, `Inner := F` -- the enclosing function's name, bare, parameterless, in a READ position -- compiles to a recursive CALL to F. fpc 3.2.2 reads the enclosing function's RESULT VARIABLE and does not call anything. Measured with a call counter so the two readings cannot be confused: fpc `calls=1`, pxx `calls=2`, pin v407 `calls=2` (so it predates the 2026-09-07 nested-result work and is untouched by it). The WRITE spellings are all correct now -- `F := x`, `F.FV := x`, `F[i] := x`, `F^ := x` from a nested procedure or function -- so this is the last position where the enclosing name does not mean the result. NOT a trivial widening of the same rewrite: rewriting a bare READ unconditionally would silently stop a genuine parameterless recursive call from a nested routine, so the fix has to decide what `F` with no parentheses means, and that is a dialect decision more than a parser one."
---

# Repro — the counter is the point

```pascal
program bare; {$mode objfpc}{$H+}
var calls, depth: LongInt;
function F: LongInt;
  function Inner: LongInt;
  begin
    if depth = 0 then begin Inc(depth); Inner := F; end else Inner := -1;
  end;
begin
  Inc(calls);
  Result := 40 + depth;
  WriteLn('  inner=', Inner, ' res=', Result, ' calls=', calls);
end;
begin calls := 0; depth := 0; WriteLn('final=', F, ' calls=', calls); end.
```

```
fpc 3.2.2      final=  inner=40 res=40 calls=1
               40 calls=1
pxx HEAD       inner=-1 res=41 calls=2 ... 40 calls=2
pin v407       identical to HEAD
```

**A value comparison alone could not have settled this** — the two readings can
produce the same number for the right depth. `calls` is the row that separates
them, and it is why the probe carries a counter rather than only a result.

# Why this is not one more token kind in the existing rewrite

`ParseNestedRoutine`'s enclosing-name rewrite now fires on `:=`, `.`, `[` and
`^`. Every one of those is unambiguously a result POSITION. A bare name in a
read position is the one spelling where a recursive call is a real competing
reading, and `test_a_nested_routine_assigns_the_enclosing_functions_result.pas`
carries `Recurse := Recurse(k - 1) + 1` as the control — though note that row is
**parenthesised**, so it does not actually exercise this question. There is no
in-tree assertion either way for a bare parameterless read.

So the choice is a dialect decision:

- **Match fpc**: inside a nested routine the enclosing name is always the result
  variable, and a recursive call must be spelled `F()`. This is old-Turbo-Pascal
  behaviour and is what fpc measurably does.
- **Keep today's**: a bare read is a call, which is what the name means in the
  enclosing function's OWN body.

Whichever is chosen, the two positions (own body vs nested routine) currently
agree with each other and disagree with fpc in the nested one. Say which
behaviour is intended in the ticket before touching the rewrite, and add the
counter probe as a row — a fixture asserting only the returned value will pass
under both readings for most depths.

# Not urgent

No in-tree code and no corpus row is known to spell it. Found while fixing
`bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results`,
as the one remaining position after every WRITE spelling was closed.
