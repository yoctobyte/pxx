{ Dynamic-array concatenation: `Concat(a, b, ...)` and `a + b`.

  Both spellings build the SAME node (the array-splice AN_DYN_INSERT with the
  index pinned past the end), which is the point -- with two lowerings the
  second one is the one that stays broken. So every row below is run through
  BOTH spellings wherever FPC accepts both.

  Expected output is fpc 3.2.2 (`-Mobjfpc -O1`, {$modeswitch arrayoperators}).
  feature-p-dynamic-array-concatenation }
{$mode objfpc}{$H+}
{$modeswitch arrayoperators}
program test_dynamic_array_concatenation;
type
  TIA = array of Integer;
  TSA = array of string;
  TMA = array of TIA;
var
  a, b, c, e: TIA;
  s, t, u: TSA;
  m, n, o: TMA;
  i: Integer;

function MkI: TIA;
begin SetLength(Result, 2); Result[0] := 7; Result[1] := 8; end;

procedure DumpI(const p: array of Integer);
var k: Integer;
begin
  Write(Length(p), ':');
  for k := 0 to Length(p) - 1 do Write(' ', p[k]);
  Writeln;
end;

begin
  SetLength(a, 2); a[0] := 1; a[1] := 2;
  SetLength(b, 1); b[0] := 3;

  { the two spellings, same answer }
  c := Concat(a, b);
  DumpI(c);
  c := a + b;
  DumpI(c);

  { an empty operand on either side, and both empty -- a nil handle is length 0
    through PXXDynLen, so these are copies rather than a special case }
  DumpI(Concat(e, a));
  DumpI(Concat(a, e));
  DumpI(Concat(e, e));

  { n-ary: the fold is left-associative, exactly as the string Concat's is }
  DumpI(Concat(a, b, a));

  { the destination ALIASES an operand -- the fresh buffer is filled before the
    handle is swapped, so this must not read freed memory }
  a := a + b;
  DumpI(a);
  a := b + a;
  DumpI(a);

  { managed element type: the concatenated elements gain the ref the new buffer
    owns, and the old buffer's element-aware release fires on the swap }
  SetLength(s, 2); s[0] := 'al'; s[1] := 'be';
  SetLength(t, 1); t[0] := 'ga';
  u := Concat(s, t);
  Write(Length(u), ':');
  for i := 0 to Length(u) - 1 do Write(' ', u[i]);
  Writeln;
  u := u + u;                     { both operands alias the destination }
  Write(Length(u), ':');
  for i := 0 to Length(u) - 1 do Write(' ', u[i]);
  Writeln;

  { nested: the elements are sub-array HANDLES, moved at pointer stride and
    retained per level }
  SetLength(m, 1, 2); m[0][0] := 5; m[0][1] := 6;
  SetLength(n, 1, 1); n[0][0] := 9;
  o := Concat(m, n);
  Writeln(Length(o), ' ', o[0][1], ' ', o[1][0]);

  { a CALL result as an operand. The insertion index is a pinned constant and
    not a `Length(a)` node precisely so this calls MkI once per occurrence. }
  DumpI(Concat(MkI, b));
  DumpI(MkI + MkI);

  { a concat as an operand of another concat, and as a Length() argument }
  DumpI(Concat(a, b) + b);
  Writeln(Length(Concat(a, b)));
end.
