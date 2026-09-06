{ Pascal lets a nested routine write the ENCLOSING function's result by using
  the function's own name on the left of `:=`. fcl-passrc's pscanner.pp does it
  twice (`:3075`, `:3082`), and pxx had no arm for it: for a free function the
  name reached FindSym and answered `undefined variable`, and for a METHOD it
  resolved to the method and produced two diagnostics about a CALL -- `wrong
  number of parameters` and then `cannot assign to the result of a function
  call` -- neither of which mentions a result variable.

  `Result := ...` from a nested routine has always worked, so this was a
  spelling that never reached a working mechanism rather than a missing one.

  THE LAST ROW IS THE CONTROL AND IT IS THE WHOLE RISK OF THE FIX. Inside a
  function the bare name is ALSO a recursive call, and the two readings are
  separated only by whether `:=` follows. `Recurse := Recurse(k - 1) + 1` has
  both in one statement: the left is the result variable and the right is a
  genuine recursive call. A fix that rewrote the name unconditionally would
  turn the right-hand side into a result READ and print 0 -- a wrong number,
  not a build failure.
  bug-p-a-nested-routine-cannot-assign-the-enclosing-functions-result }
{$mode objfpc}
program test_a_nested_routine_assigns_the_enclosing_functions_result;
type
  TC = class
    N: Integer;
    function Scan(k: Integer): Integer;
    function Recurse(k: Integer): Integer;
  end;

{ a free function, with a captured local in the mix }
function Outer(x: Integer): Integer;
var acc: Integer;
  procedure Bump;
  begin
    acc := acc + 1;
    Outer := acc * 10;
  end;
begin
  acc := x;
  Outer := 0;
  Bump;
  Bump;
end;

{ ...and one with nothing captured but the result itself }
function Plain(x: Integer): Integer;
  procedure Set2;
  begin
    Plain := 2;
  end;
begin
  Plain := 1;
  Set2;
end;

{ a METHOD: Procs[].Name carries the owner prefix and the source does not }
function TC.Scan(k: Integer): Integer;
  procedure Finish;
  begin
    Scan := N * 100;
  end;
begin
  Scan := k;
  N := 4;
  Finish;
end;

{ the control: a result WRITE whose right-hand side is a real recursive CALL }
function TC.Recurse(k: Integer): Integer;
  procedure Step;
  begin
    if k > 0 then
      Recurse := Recurse(k - 1) + 1
    else
      Recurse := 0;
  end;
begin
  Step;
end;

var c: TC;
begin
  WriteLn('outer=', Outer(5));
  WriteLn('plain=', Plain(0));
  c := TC.Create;
  WriteLn('scan=', c.Scan(1));
  WriteLn('recurse=', c.Recurse(3));
end.
