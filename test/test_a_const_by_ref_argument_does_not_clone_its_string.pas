{ `Move(s[i], c, 1)` with a `const` string s: Move's source is an untyped
  CONST by-reference parameter, an address the callee only reads. wasm32 walked
  every by-ref argument in write position, so `s[i]` ran copy-on-write on s,
  and the clone went into the const parameter's slot, which nobody releases.
  sysutils' Copy is exactly SetLength + that Move, so Copy of a literal or of
  a shared string leaked one block per call there, and JSONParse leaked one
  per number. Its leak row (assert_no_leak, -dPXX_ALLOC_CENSUS) is what sees
  it; the output is the same either way.
  bug-a-wasm32-a-const-by-ref-argument-clones-the-string-it-indexes }
program test_a_const_by_ref_argument_does_not_clone_its_string;
{$mode objfpc}{$H+}
uses sysutils;

function FirstOrd(const s: AnsiString): Integer;
var c: Char;
begin
  Move(s[1], c, 1);
  Result := Ord(c);
end;

var
  i, sum: Integer;
  s, t, u: AnsiString;
begin
  sum := 0;
  t := 'shared' + IntToStr(7);
  u := t;                          { t is now shared: rc 2 }
  for i := 1 to 400 do
  begin
    sum := sum + FirstOrd('xyz');  { a literal }
    sum := sum + FirstOrd(t);      { a shared heap string }
    s := Copy('hello', 2, 3);
    s := Copy(t, 1, 3);
  end;
  t[1] := 'S';                     { a real write still unshares }
  WriteLn(sum, ' ', s, ' ', t, ' ', u);
end.
