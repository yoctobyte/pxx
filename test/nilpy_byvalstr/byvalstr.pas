unit byvalstr;
{ A Pascal unit whose routines take BY-VALUE AnsiStrings, driven from a NilPy
  program by test_nilpy_a_pascal_unit_owns_its_by_value_strings.npy. The calls
  that matter are Pascal-to-Pascal INSIDE the unit: the NilPy boundary copies,
  and would hide the defect. }
interface
function InPlace: AnsiString;
function Rebinds(k: Integer): AnsiString;
implementation

{ writes its by-value copy in place: the caller's string must not change }
function UpFirst(s: AnsiString): AnsiString;
begin
  s[1] := 'X';
  UpFirst := s;
end;

function InPlace: AnsiString;
var a, r: AnsiString;
begin
  a := 'hello';
  a := a + '!';
  r := UpFirst(a);
  InPlace := a + ' ' + r;
end;

{ rebinds its by-value param, from a nested routine, with the argument shared
  by two locals -- the held repr patch's TryCand shape }
function Rebinds(k: Integer): AnsiString;
var ds0, ds, found: AnsiString; i, sig: Integer;
  function TryIt(digits: AnsiString; n: Integer): Boolean;
  var tail: Integer;
  begin
    TryIt := False;
    tail := Length(digits);
    while (tail > 1) and (digits[tail] = '0') do tail := tail - 1;
    digits := Copy(digits, 1, tail);
    if Length(digits) < n then Exit;
    found := digits + 'e';
    TryIt := True;
  end;
begin
  found := '';
  for i := 1 to k do
  begin
    ds0 := 'ab' + Chr(48 + i mod 10) + '000';
    for sig := 5 downto 1 do
    begin
      ds := ds0;
      if TryIt(ds, sig) then Break;
    end;
  end;
  Rebinds := found + ' ' + ds0 + ' ' + ds;
end;
end.
