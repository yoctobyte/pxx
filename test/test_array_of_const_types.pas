program test_array_of_const_types;

{ `array of const` element-type coverage: every element kind the lowering now
  tags — vtInteger, vtBoolean, vtChar, vtInt64 (boxed), vtExtended (boxed),
  vtAnsiString — read back by tag through the matching TVarRec union field. Int64
  and Double are boxed (the union slot is pointer-sized) so they round-trip with
  full width on 32-bit targets too. Output must be byte-identical across all
  targets (the string is walked char-by-char to avoid the write(PChar) gap). }

type
  PI64 = ^Int64;
  PD = ^Double;
  PB = ^Byte;

procedure show(const items: array of const);
var i: Integer; p: PB;
begin
  for i := 0 to Length(items) - 1 do
  begin
    write('vt', items[i].VType, ': ');
    if items[i].VType = vtInteger then writeln(items[i].VInteger)
    else if items[i].VType = vtBoolean then writeln(items[i].VBoolean)
    else if items[i].VType = vtChar then writeln(items[i].VChar)
    else if items[i].VType = vtInt64 then writeln(PI64(items[i].VInt64)^)
    else if items[i].VType = vtExtended then writeln(PD(items[i].VExtended)^:0:2)
    else if items[i].VType = vtAnsiString then
    begin
      p := PB(items[i].VAnsiString);
      while p^ <> 0 do begin write(Chr(p^)); p := PB(PChar(Pointer(p)) + 1); end;
      writeln;
    end
    else writeln('?');
  end;
end;

var b: Boolean; c: Char; n: Int64; d: Double; s: AnsiString;
begin
  b := True; c := 'Q'; n := 5000000000; d := 3.5; s := 'hi';
  show([42, b, c, n, d, s]);
end.
