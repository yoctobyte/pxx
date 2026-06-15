program test_cross_var_string_param;

{ Reading a managed AnsiString through a var (by-ref) parameter must deref the
  forwarded caller slot to the handle before Length / index. Regression for the
  ARM32 bug where Length(var dst) returned 0 (one deref short), which made
  AppendChar/SetLength-grown strings collapse to one char and tripped
  "Pascal define storage overflow" in the self-hosted compiler. }

function GetLen(var dst: AnsiString): Integer;
begin
  GetLen := Length(dst);
end;

function FirstChar(var dst: AnsiString): Char;
begin
  FirstChar := dst[1];
end;

procedure AppendCh(var dst: AnsiString; c: Char);
var len: Integer;
begin
  len := Length(dst);
  SetLength(dst, len + 1);
  dst[len + 1] := c;
end;

function Tail(const value: AnsiString; first: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  i := first;
  while i <= Length(value) do
  begin
    AppendCh(Result, value[i]);
    i := i + 1;
  end;
end;

var
  acc, t: AnsiString;
begin
  acc := 'ABCDE';
  writeln('varlen=', GetLen(acc));
  writeln('firstchar=', FirstChar(acc));
  t := Tail('-dPXX_MANAGED_STRING', 3);
  writeln('tail=[', t, ']');
  writeln('taillen=', Length(t));
end.
