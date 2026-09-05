{ A generic ROUTINE has two surfaces and pxx accepted exactly one of them.

  objfpc:  generic function Add<T>(...)  called as  specialize Add<C>(...)
  Delphi:          function Add<T>(...)  called as            Add<C>(...)

  Both spellings are in this ONE row on purpose: either alone passes against a
  compiler that broke the other, and the defect was that they disagreed. fpc
  3.2.2 accepts both and prints exactly what is asserted below.

  The Delphi surface is also the case where the USE site is ambiguous -- a bare
  `Add<LongInt>(2, 3)` is `a < b > (c)` to a parser that does not know Add is a
  generic routine -- so `Cmp` below is the control for the other direction: the
  same shape, spelled with names that are NOT generic routines, must still
  compile as two comparisons. Without it the specialization sweep would be free
  to eat every `x < y > (z)` in the language and this row would not notice.
  fpc cannot hold both surfaces in ONE file -- `-Mobjfpc` refuses the Delphi
  header at line 24 and `-Mdelphi` refuses the `generic` keyword at line 19 --
  so the oracle diff was run per HALF (each half's own program, byte-identical
  output, 2026-09-05) and this row asserts the union. That is the pxx dialect
  being one objfpc-ish superset, not a divergence.
  feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling }
program test_generic_routine_both_spellings;

type
  { The header the routine test must NOT claim. `function TBox<T>.Echo` is a
    generic CLASS's method implementation, and it opens with the same three
    tokens a generic routine does -- `function` ident `<`. What separates them
    is the token AFTER the group: a routine has `(`, `:` or `;` there, a class
    method has `.`. Getting that wrong made pxx ACCEPT tgeneric31, a `%FAIL` row
    whose whole point is a method header naming one type parameter where the
    class declared two.

    This row is here because the corpus could not catch it: measured with the
    loose predicate on purpose, an ordinary specialized generic class still
    compiled and still printed the right answer -- the specialized case is
    desugared before the dispatcher sees it and is immune by coincidence. }
  TBox<T> = class
    function Echo(a: T): T;
  end;

function TBox<T>.Echo(a: T): T;
begin
  Result := a;
end;

generic function GAdd<T>(aLeft, aRight: T): T;
begin
  Result := aLeft + aRight;
end;

function DAdd<T>(aLeft, aRight: T): T;
begin
  Result := aLeft + aRight;
end;

var
  a, b: Integer;
  c: Boolean;
  bx: TBox<Integer>;
begin
  WriteLn('objfpc ', specialize GAdd<Integer>(2, 3));
  WriteLn('objfpc ', specialize GAdd<String>('Hello', 'World'));
  WriteLn('delphi ', DAdd<Integer>(2, 3));
  WriteLn('delphi ', DAdd<String>('Hello', 'World'));
  a := 1; b := 9;
  c := a < b;
  WriteLn('cmp ', c);
  bx := TBox<Integer>.Create;
  WriteLn('classmeth ', bx.Echo(7));
end.
