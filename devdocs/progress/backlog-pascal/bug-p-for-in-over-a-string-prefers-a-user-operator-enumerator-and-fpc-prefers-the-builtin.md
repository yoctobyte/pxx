---
slug: bug-p-for-in-over-a-string-prefers-a-user-operator-enumerator-and-fpc-prefers-the-builtin
track: P
prio: 30
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-07
found-by: frankS
summary: "With `operator enumerator(a: AnsiString)` in scope, `for ch in s` runs the OPERATOR; fpc 3.2.2 iterates the string's characters. Measured on the PINNED compiler as well as HEAD, so it predates the for-in expression work that turned it up. Silent: both spellings compile and produce a plausible wrong value. The rule to adopt is fpc's -- a built-in iteration meaning wins over a user operator on the same type -- but the fix must move the SYMBOL arm and the EXPRESSION arm together or the two spellings diverge."
---

# for-in over a string prefers a user `operator enumerator`; fpc prefers the builtin

```pascal
{$mode objfpc}
type TEnum = class
  stop: Boolean; F: Integer;
  function MoveNext: Boolean;
  property Current: Integer read F;
end;
function TEnum.MoveNext: Boolean; begin Result := not stop; stop := True; end;
operator enumerator(a: AnsiString): TEnum;
begin Result := TEnum.Create; Result.F := 99; Result.stop := False; end;
var ch: Char; s1, s2: AnsiString;
begin
  s1 := 'ab'; s2 := 'c';
  for ch in s1 do write(ch, ' ');        writeln;
  for ch in s1 + s2 do write(ch, ' ');   writeln;
end.
```

| container | fpc 3.2.2 | pxx HEAD | pxx PINNED (v407) |
| --- | --- | --- | --- |
| `s1` (variable) | `a b` | `c` | `c` |
| `s1 + s2` (expression) | `a b c` | `c` | `c` |

`c` is `Chr(99)` — the operator's own `F`, read back through a `Char` loop
variable. So it is not a refusal and not a crash: the program compiles and
prints a plausible string.

**It predates the work that found it.** The pinned compiler answers `c` for both
spellings, so this is not fallout from
[[bug-p-for-in-over-a-scalar-expression-never-reaches-the-enumerator-operator]];
that fix made the expression spelling behave like the variable spelling, which
is the normalisation this file's own dispatch asks for, and the shared behaviour
is the one that diverges.

## Why it is worth taking

Iterating a string is the common case and a user operator on `AnsiString` is the
rare one, so the wrong answer lands on the code that did not opt in: declaring
one operator anywhere in a unit silently changes every `for ch in <string>` that
can see it. fpc's rule is the safe one — a type with a built-in iteration meaning
keeps it, and the operator applies where no built-in meaning exists.

## Where, and the trap

`compiler/pasparser_stmt.inc`. Two decision points, and they must move together:

1. The SYMBOL arm (~1396) asks `FindOpOverload(OPK_ENUMERATOR, ...)` for
   `TypeIsFrozenString`/`tyAnsiString` containers **before** falling through to
   string iteration. That order is the bug.
2. The EXPRESSION dispatch (~3300) already runs its string arm before the
   operator arm, i.e. it is already in fpc's order.

So the fix is to the FIRST one — but changing it alone leaves the two arms
agreeing today by accident rather than by rule, and this dispatch's own comments
record twice that two arms deciding independently what a container means is how
one spelling stays broken while its twin works. State the rule once.

**Not measured:** whether the same inversion exists for the other container
families that have a built-in meaning (sets, dyn-arrays). The probe above only
covers strings. Check before writing the rule, because a rule stated for one
family and applied to three is the shape this file keeps warning about.
