{ `Default(T)` yielded the integer 0 for EVERY T, so an aggregate type had no
  zero value at all:

    a := Default(TRec);    { copied RecSize bytes from address 0 -> SIGSEGV }
    ar := Default(TArr);   { stored an integer into an array slot -- SILENT:
                             every element kept its old value }

  The array half is the expensive one: a dirty array stayed dirty and nothing
  said so. Zero of an aggregate is a whole zeroed OBJECT, so the compiler now
  materialises one -- a hidden static (BSS, zero-filled at load) of that exact
  type, which nothing can write to because Default() is an rvalue. The ordinary
  record/array copy does the rest, managed fields included. A CLASS keeps the
  integer 0, which is its correct nil.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-default-of-a-record-segfaults-of-an-array-does-nothing }
program test_default_of_aggregate;
{$mode objfpc}{$H+}
uses sysutils;

type
  TPt   = record x, y: Integer; end;
  TNest = record p: TPt; tag: string; n: array[0..2] of Integer; end;
  TArr  = array[0..3] of Integer;
  TSArr = array[0..2] of string;
  TDyn  = array of Integer;
  TEn   = (eA, eB, eC);
  TCls  = class end;
  TBox  = record inner: TNest; k: Integer; end;

var
  ok, total: Integer;
  a: TPt; nn: TNest; ar: TArr; sa: TSArr; dy: TDyn; bx: TBox;
  i: Integer; s: string; d: Double; b: Boolean; p: Pointer; e: TEn; c: TCls;

procedure Chk(const what: string; got, want: Int64);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ChkS(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

function SumArr(const q: TArr): Integer;
var j: Integer;
begin Result := 0; for j := 0 to High(q) do Result := Result + q[j]; end;

procedure LocalDefaults;
{ inside a routine: the hidden zero must be static BSS, not a stack temp }
var la: TPt; lr: TArr; j: Integer;
begin
  la.x := 11; la.y := 12;
  for j := 0 to 3 do lr[j] := 5;
  la := Default(TPt);
  lr := Default(TArr);
  Chk('local rec x', la.x, 0);
  Chk('local rec y', la.y, 0);
  Chk('local arr sum', SumArr(lr), 0);
end;

begin
  ok := 0; total := 0;

  { ---- the scalars that always worked, so the fix did not move them ---- }
  i := 7;   i := Default(Integer);   Chk('Default(Integer)', i, 0);
  b := True; b := Default(Boolean);  Chk('Default(Boolean)', Ord(b), 0);
  d := 1.5; d := Default(Double);    Chk('Default(Double)', Trunc(d * 10), 0);
  p := @i;  p := Default(Pointer);   Chk('Default(Pointer)', Ord(p = nil), 1);
  e := eC;  e := Default(TEn);       Chk('Default(TEn)', Ord(e), 0);
  s := 'zz'; s := Default(string);   Chk('Default(string)', Length(s), 0);
  c := TCls.Create;
  c := Default(TCls);                Chk('Default(TCls) is nil', Ord(c = nil), 1);
  dy := nil; SetLength(dy, 3);
  dy := Default(TDyn);               Chk('Default(TDyn)', Length(dy), 0);

  { ---- the record that used to SEGFAULT ---- }
  a.x := 5; a.y := 6;
  a := Default(TPt);
  Chk('Default(TPt).x', a.x, 0);
  Chk('Default(TPt).y', a.y, 0);

  { ---- the array that used to do nothing at all ---- }
  for i := 0 to 3 do ar[i] := 7;
  Chk('dirty array sums', SumArr(ar), 28);
  ar := Default(TArr);
  Chk('Default(TArr) sums', SumArr(ar), 0);
  Chk('Default(TArr)[3]', ar[3], 0);

  { ---- a record with managed and array fields ---- }
  nn.p.x := 1; nn.p.y := 2; nn.tag := 'hello'; nn.n[1] := 9;
  nn := Default(TNest);
  Chk('nested rec p.x', nn.p.x, 0);
  Chk('nested rec p.y', nn.p.y, 0);
  Chk('nested rec tag len', Length(nn.tag), 0);
  ChkS('nested rec tag', nn.tag, '');
  Chk('nested rec n[1]', nn.n[1], 0);

  { ---- a record whose first field is itself a record ---- }
  bx.inner.tag := 'x'; bx.inner.p.x := 3; bx.k := 4;
  bx := Default(TBox);
  Chk('box inner.p.x', bx.inner.p.x, 0);
  Chk('box inner tag len', Length(bx.inner.tag), 0);
  Chk('box k', bx.k, 0);

  { ---- an array of managed elements ---- }
  sa[0] := 'a'; sa[1] := 'b'; sa[2] := 'c';
  sa := Default(TSArr);
  Chk('str array [0] len', Length(sa[0]), 0);
  Chk('str array [2] len', Length(sa[2]), 0);

  { ---- the hidden zero must survive being used twice, and stay zero ---- }
  a := Default(TPt); a.x := 42;
  a := Default(TPt);
  Chk('second Default is still zero', a.x, 0);
  for i := 1 to 3 do
  begin
    nn := Default(TNest);
    nn.p.x := i;
  end;
  nn := Default(TNest);
  Chk('Default in a loop stays zero', nn.p.x, 0);

  { ---- as a value argument ---- }
  Chk('SumArr(Default(TArr))', SumArr(Default(TArr)), 0);

  LocalDefaults;

  writeln('total ok ', ok, ' / ', total);
end.
