{ A routine declared in the compiling scope must win an unqualified call over a
  same-named one from a used unit, and a qualified call must still reach the
  unit's. The chain is registration order and units register first, so this used
  to silently call the unit's version
  (bug-p-program-function-does-not-shadow-used-unit). }
program test_shadow_program_over_unit;
uses sysutils;
function IntToStr(v: Int64): AnsiString; begin IntToStr := 'mine'; end;
function Trim(const t: AnsiString): AnsiString; begin Trim := 'mine-trim'; end;
{ Shadowing a BUILTIN already worked and must keep working. }
function UpCase(c: Char): Char; begin UpCase := 'X'; end;
var a: AnsiString;
begin
  a := ' x ';
  writeln(IntToStr(Int64(5)));
  writeln(Trim(a));
  writeln(UpCase('a'));
  writeln(sysutils.IntToStr(Int64(7)));
end.
