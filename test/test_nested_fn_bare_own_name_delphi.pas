program test_nested_fn_bare_own_name_delphi;
{ The {$mode delphi} arm of the same guard, and the reason it is a separate
  file: in Delphi a bare own-name read is a reference to the ROUTINE, not to
  the result var, so a paramless one is a recursive CALL and the nested-routine
  hoist pass must keep splicing the hidden capture actuals onto it.
  pasparser_expr.inc's own-name-read branch is guarded `not DelphiMode` for
  exactly this reason; the guard in pasparser_decl.inc mirrors it, and this file
  is the row that fails if the two ever stop agreeing.

  Without the mode carve-out this prints 3 (the result read: Base after the
  decrements) instead of 100 (the recursion's base case) -- so it is a VALUE
  row, not a compiles/does-not-compile row. Read `Result :=` on the write side
  throughout: `Ping := ...` would be a write to a routine reference in Delphi.

  .expected IS fpc 3.2.2's own output on this source, unmodified.
  bug-p-a-nested-functions-bare-own-name-read-is-compiled-as-a-recursive-call }
{$mode delphi}

procedure Run;
var
  Base: Integer;
  Hits: Integer;

  function Ping: Integer;
  begin
    Dec(Base);
    Inc(Hits);
    if Base > 0 then Result := Ping else Result := 100;
  end;

begin
  Base := 3; Hits := 0;
  WriteLn('ping = ', Ping);
  WriteLn('hits = ', Hits);
end;

begin
  Run;
end.
