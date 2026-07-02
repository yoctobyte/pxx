program test_soft_keyword_length;
{ `Length`/`Ord`/`Chr`/`Low`/`High` are soft keywords (lex as plain
  identifiers, ParseFactor dispatches on the name) —
  bug-hard-keyword-intrinsics-block-identifier-use. FPC-parity pinned here:
  all five are declarable as variable/param/field names; the intrinsics are
  untouched where the name is not shadowed (a shadowing var makes `Length(x)`
  a compile error in FPC — kept, but not testable in a green test). }
type TE = (eA, eB, eC);
var
  okCount: Integer;
  s: string;
  a: array of Integer;
  f: array[0..4] of Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;

{ param named Length: legal, reads as a plain value inside }
function ParamShadow(Length: Integer): Integer;
begin ParamShadow := Length * 2; end;

{ local var named length: legal; shadows the intrinsic only in this scope }
function LocalShadow: Integer;
var length: Integer;
begin length := 21; LocalShadow := length + 21; end;

{ record field named Length }
type TBuf = record Length: Integer; end;

{ user function named Length shadows the intrinsic at its call sites }
function UserArea: Integer;
begin UserArea := 0; end;

var r: TBuf;

{ ord/chr/low/high declarable and usable as plain locals }
function OrdChrLowHighVars: Integer;
var ord, chr, low, high: Integer;
begin
  ord := 1; chr := 2; low := 3; high := 4;
  OrdChrLowHighVars := ord + chr + low + high;
end;

begin
  okCount := 0;
  Chk(1, Length('hello') = 5);            { literal fold }
  s := 'worlds';
  Chk(2, Length(s) = 6);                  { string lvalue }
  SetLength(a, 3);
  Chk(3, Length(a) = 3);                  { dyn array }
  Chk(4, Length(f) = 5);                  { static array fold }
  Chk(5, LENGTH('abc') = 3);              { any casing }
  Chk(6, ParamShadow(7) = 14);
  Chk(7, LocalShadow = 42);
  r.Length := 9;
  Chk(8, r.Length = 9);
  Chk(9, Length(s + '!') = 7);            { r-value (concat result) }
  Chk(10, OrdChrLowHighVars = 10);        { ord/chr/low/high as variables }
  Chk(11, (Ord('A') = 65) and (Chr(66) = 'B') and (Ord(eC) = 2));
  Chk(12, (Low(f) = 0) and (High(f) = 4) and (High(Byte) = 255));
  Chk(13, (Low(a) = 0) and (High(a) = 2));
  Chk(14, (Low(TE) = eA) and (High(TE) = eC));
  writeln('total ok ', okCount, ' / 14');
end.
