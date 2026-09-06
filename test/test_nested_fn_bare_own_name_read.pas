program test_nested_fn_bare_own_name_read;
{ A bare own name inside a nested FUNCTION that CAPTURES something is a read of
  the result var (objfpc/default), not a recursive call. The nested-routine
  hoist pass used to split own-name occurrences two ways -- followed by `:=` is
  a result write, everything else is a recursive call -- and spliced the hidden
  capture actuals onto the "everything else" arm. A bare READ took that arm and
  came out as `F$21(Top)` against `F$21(Top; out R)`.

  THE THREE FACES ARE NOT EQUALLY VISIBLE, which is why this file asserts
  VALUES and not just "it compiles":

    reads_own_name / reads_via_result   the loud face -- an arity error naming
                                        `F$<n>`, a name the programmer never
                                        wrote, attributed to builtinheap.pas.
                                        Only loud because the routine happens
                                        to have parameters of its own.
    paramless                           SILENT: `F(Top)` matches `F(Top)`
                                        exactly, so it compiled clean and
                                        recursed forever. fpc prints 6; we
                                        segfaulted, with no diagnostic.
    selector_field / selector_index     SILENT the same way: a trailing `.f` or
                                        `[i]` on the own name is a result read
                                        too, and `Mk(Base).Row` recursed.

  Everything below `--- controls` must NOT change: a nested PROCEDURE's bare own
  name IS a recursive call, and an explicit `F()` IS one inside a function. They
  are here because the fix narrows the read/call split, so the call side needs a
  row that fails if the narrowing went one step too far.

  The delphi-mode arm of the same guard is test_nested_fn_bare_own_name_delphi.pas
  -- a bare own-name read is a routine reference there, not the result, so it
  keeps the splice and cannot be asserted in this file's mode.

  .expected IS fpc 3.2.2's own output on this source, unmodified.
  bug-p-a-nested-functions-bare-own-name-read-is-compiled-as-a-recursive-call }
{$mode objfpc}
type
  TRec = record Row, Col: Integer; end;
  TArr = array of TRec;

procedure Faces;
var
  Top: Integer;
  Stack: TArr;
  Base: Integer;

  { LOUD FACE: captures + own parameters. The read on the second line is what
    used to be spliced into a call. }
  function ReadsOwnName(out R: TRec): Integer;
  begin
    ReadsOwnName := Stack[Top].Row;
    if ReadsOwnName >= 0 then R.Row := 1 else R.Row := 0;
  end;

  { The same body written with `Result`, which always worked -- it is the
    discriminator that found this, so it stays as a row. }
  function ReadsViaResult(out R: TRec): Integer;
  begin
    Result := Stack[Top].Row;
    if Result >= 0 then R.Row := 1 else R.Row := 0;
  end;

  { SILENT FACE 1: paramless, so the spliced call was well-formed. }
  function Paramless: Integer;
  begin
    Paramless := Base;
    if Paramless >= 0 then Paramless := Paramless + 1;
  end;

  { SILENT FACE 2: a trailing selector on the own name. }
  function SelectorField: TRec;
  begin
    SelectorField.Row := Base;
    SelectorField.Col := Top;
    if SelectorField.Row < 0 then SelectorField.Row := 0;
  end;

  function SelectorIndex: TArr;
  begin
    SetLength(SelectorIndex, 2);
    SelectorIndex[0].Row := Base;
    SelectorIndex[1].Row := SelectorIndex[0].Row * 2;
  end;

var
  r: TRec;
  a: TArr;
begin
  SetLength(Stack, 2);
  Stack[0].Row := 10; Stack[1].Row := 20;
  Top := 1; Base := 5;
  WriteLn('reads_own_name  = ', ReadsOwnName(r), ' r.Row=', r.Row);
  WriteLn('reads_via_result= ', ReadsViaResult(r), ' r.Row=', r.Row);
  WriteLn('paramless       = ', Paramless);
  r := SelectorField;
  WriteLn('selector_field  = ', r.Row, ',', r.Col);
  a := SelectorIndex;
  WriteLn('selector_index  = ', a[0].Row, ',', a[1].Row);
end;

{ --- controls: the call side of the split, which must be untouched --- }
procedure Controls;
var
  Depth: Integer;
  Base: Integer;
  Stack: TArr;

  { A nested PROCEDURE has no result, so a bare own name is unambiguously a
    recursive call and still needs the capture actuals spliced. }
  procedure Down;
  begin
    if Depth > 0 then begin Dec(Depth); Down; end;
  end;

  { Explicit `F()` in a capturing PARAMLESS function: the spelling the flip
    (bug-bare-function-name-call-vs-resultvar) requires for self-recursion. }
  function Ping: Integer;
  begin
    Dec(Base);
    if Base > 0 then Ping := Ping() else Ping := 100;
  end;

  { Explicit recursive call with arguments, capturing a dynamic array. }
  function SumFrom(i: Integer): Integer;
  begin
    if i >= Length(Stack) then SumFrom := 0
    else SumFrom := Stack[i].Row + SumFrom(i + 1);
  end;

begin
  Depth := 4; Down;
  WriteLn('down            = ', Depth);
  Base := 3;
  WriteLn('ping            = ', Ping);
  SetLength(Stack, 3);
  Stack[0].Row := 1; Stack[1].Row := 2; Stack[2].Row := 4;
  WriteLn('sum_from        = ', SumFrom(0));
end;

begin
  Faces;
  Controls;
end.
