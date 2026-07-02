program test_soft_keyword_length;
{ `Length` is a soft keyword (lexes as a plain identifier, ParseFactor
  dispatches on the name) — pilot for
  bug-hard-keyword-intrinsics-block-identifier-use. FPC-parity pinned here:
  Length is declarable as a variable/param/field name; the intrinsic is
  untouched where the name is not shadowed (a shadowing var makes `Length(x)`
  a compile error in FPC — kept, but not testable in a green test). }
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
  writeln('total ok ', okCount, ' / 9');
end.
