---
prio: 60
track: P
status: done
summary: "`Outer.FV := 33` inside a nested routine is compiled as a recursive CALL to Outer, not as a write to the enclosing result: the program spins until it segfaults. The enclosing-name rewrite in ParseNestedRoutine only fires when the NEXT token is `:=`, which is the correct discriminator for a bare name (where the other reading really is recursion) and the wrong one for a QUALIFIED write, whose `.` can never begin a recursive-call argument list. Hits nested PROCEDURES as well as nested functions, so it is not the same defect as the bare-name one. Measured identical on pin v407 and at HEAD 14d483f74974."
owner: frankS
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

# FIXED — and the ticket's own "shape of the fix" was right where I was cautious

`compiler/pasparser_decl.inc`, ParseNestedRoutine's enclosing-name rewrite: the
discriminator is now `:=` **or** a selector (`.`, `[`, `^`) on the next token,
for a nested **PROCEDURE**. Fixture
`test/test_a_nested_routine_can_write_the_enclosing_result_through_a_selector.pas`
(`test_nestselwrite26`), six rows, all against fpc 3.2.2.

## The cautious rule is the wrong one, and I built it before measuring

I first wrote a helper that walked the selector chain and rewrote only if it
ended at `:=`, reasoning that a qualified name on the RIGHT must be a call —
`x := Outer.FV` calls Outer and reads a field of the result. That is what this
ticket implies too, in the sentence "after a `.`, recursion is not a competing
reading at all". **fpc 3.2.2 says the reading is not competing in EITHER
position:**

| row | source | fpc |
| --- | --- | --- |
| `rmw` | `Outer.FV := Outer.FV + 6`, result starts at 60 | **66** |
| `read` | nested `gRead := Outer.FV`, entered once behind a depth counter | **70**, not 71 |

Under the cautious rule the right-hand `Outer.FV` in `rmw` stays a call and the
program never returns. So a function's name **carrying a selector is the result
variable in either position**, and only a BARE name has the two readings the
`:=` test exists to separate. The helper is gone; the condition is a token-kind
set.

The two values in the `read` row differ deliberately: the outer call sets
`FV := 70 + depth` so a re-entry would answer 71. With both at 70 the row could
not tell a call from a read — the expected value would have collided with the
failure value.

`(` is deliberately not in the set, so `Outer(x).F` stays a call.

## Nested PROCEDURE only, and that is the other ticket rather than caution

The rewrite's target is the token `Result`, which inside a nested **function**
names THAT function's result. Widening this to a nested function would trade an
unbounded recursion for a **silent** write to the wrong variable, which is
strictly worse — the enclosing result needs a distinct spelling first.
[[bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results]]
A nested function keeps today's behaviour, and the fixture says so in its header
rather than asserting it: the row still recurses and cannot be run, and
asserting a crash is not an assertion.

## Controls green
`test_a_nested_routine_assigns_the_enclosing_functions_result` (the bare name's
two readings) and `test_a_nested_functions_own_result_is_not_the_enclosing_ones`
both pass unchanged.

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ca98b9782.
