---
prio: 60
track: P
status: open
summary: "`Outer.FV := 33` inside a nested routine is compiled as a recursive CALL to Outer, not as a write to the enclosing result: the program spins until it segfaults. The enclosing-name rewrite in ParseNestedRoutine only fires when the NEXT token is `:=`, which is the correct discriminator for a bare name (where the other reading really is recursion) and the wrong one for a QUALIFIED write, whose `.` can never begin a recursive-call argument list. Hits nested PROCEDURES as well as nested functions, so it is not the same defect as the bare-name one. Measured identical on pin v407 and at HEAD 14d483f74974."
---

## Repro

```pascal
program p1;
{$mode objfpc}{$H+}
type TBox = class FV: LongInt; end;
function Outer: TBox;
  procedure P;
  begin
    Outer.FV := 33;        { qualified enclosing name, from a nested PROCEDURE }
  end;
begin
  Result := TBox.Create;
  Result.FV := 1;
  P;
  WriteLn('fv=', Result.FV);
end;
begin WriteLn('final=', Outer.FV); end.
```

| | |
| --- | --- |
| fpc 3.2.2 | `fv=33` / `final=33` |
| pxx, pin v407 and HEAD `14d483f74974` | prints `final=` then **SIGSEGV** (stack exhausted by unbounded recursion) |

`Result.FV := 33` in the same position works. So does `Outer := ...`. It is the
combination — enclosing NAME, then a qualifier — that has no path.

## Cause

`ParseNestedRoutine`, `compiler/pasparser_decl.inc`, the enclosing-name rewrite:

```pascal
if (CurProc >= 0) and (i + 1 < TokCount) and
   (Tokens[i + 1].Kind = tkAssign) and
   CaseEqual(nm, UnqualifiedRoutineName(Procs[CurProc].Name)) and
   (FindSym('Result') >= 0) then
```

The `tkAssign` test is deliberate and its comment says why: inside a function the
bare name is ALSO a recursive call, and only a following `:=` separates the two
readings — `Recurse := Recurse(k - 1) + 1` has both in one statement, and
`test_a_nested_routine_assigns_the_enclosing_functions_result.pas` carries that
control. **The test is right for a bare name and does not generalise.** After a
`.`, recursion is not a competing reading at all: `Outer.FV` cannot be a call,
because a call's argument list cannot start with a field selector. The rewrite
declines anyway and the name falls through to the ordinary
identifier path, which resolves it as the routine and emits a call.

## The failure is quiet in the worst way

**No diagnostic.** The compiler accepts the unit, and the only symptom is a
segfault at run time in a program with no obvious recursion in it. A wrong
answer would at least be a value; this is a hang that ends in a signal, and the
crash location is a stack frame of `Outer` that names nothing about the nested
routine.

## Shape of the fix

Widen the discriminator from "next token is `:=`" to "next token is `:=` OR the
name is being QUALIFIED" — `.`, `[`, `^` — since none of those can begin a
recursive call's arguments. Keep the existing control green: a bare name NOT
followed by `:=` must stay a recursive call.

Both readings of a bare `Outer` are already exercised; add a qualified row for
each of `.`, `[` and `^`, and one for a nested PROCEDURE as well as a nested
FUNCTION, because the two reach this line by different routes.

## Related

- [[bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results]]
  — the BARE name in a nested FUNCTION, a different defect with a different fix.
- `test/test_a_nested_functions_own_result_is_not_the_enclosing_ones.pas`
  (`test_nestownres26`) records this row in its header as deliberately not
  asserted.
