program test_unit_const_vs_field;
{ FPC scope order inside a method body: the class's OWN field beats a unit-level
  name; only a genuine local or parameter shadows the field
  (bug-unit-const-shadows-a-field). `lib/rtl/re.pas` exports Python's DOTALL as
  `S = 4` and `lib/rtl/pathlib.pas`'s Path keeps its text in a field called `s`,
  so `uses re, pathlib` used to break pathlib from the inside. Self-checking;
  values are FPC-differential (verified against fpc {$mode objfpc}). FPC rejects a
  LOCAL of the same name as a field outright ("Duplicate identifier"), so the
  local-shadows case is not expressible here. }

const
  S = 4;                 { unit const — must not capture ZBox's field `s` }
  Count = 100;

type
  ZBox = class
    s: AnsiString;
    Count: Integer;
    constructor Create(const v: AnsiString);
    function FirstIsA: Boolean;
    function ReadUnitConst: Integer;
  end;

constructor ZBox.Create(const v: AnsiString);
begin
  s := v;                { write -> the FIELD, not the const }
  Count := 7;
end;

function ZBox.FirstIsA: Boolean;
begin
  FirstIsA := False;
  if s[1] = 'a' then FirstIsA := True;   { read -> the FIELD too }
end;

function ZBox.ReadUnitConst: Integer;
begin
  ReadUnitConst := Count;  { the field, 7 — not the unit const 100 }
end;

{ A plain routine (no Self) still sees the unit const. }
function OutsideAMethod: Integer;
begin
  OutsideAMethod := S + Count;
end;

var
  b: ZBox;
  fails: Integer;

procedure Check(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;
  b := ZBox.Create('abc');
  if not b.FirstIsA then
  begin
    WriteLn('FAIL FirstIsA');
    Inc(fails);
  end;
  if b.s <> 'abc' then
  begin
    WriteLn('FAIL field value: ', b.s);
    Inc(fails);
  end;
  Check('ReadUnitConst', b.ReadUnitConst, 7);
  Check('OutsideAMethod', OutsideAMethod, 104);
  Check('unit const S', S, 4);
  if fails = 0 then WriteLn('UNIT CONST VS FIELD OK') else WriteLn('FAILURES: ', fails);
end.
