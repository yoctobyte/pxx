program test_frozen_arg_no_leak;

{ The half of the frozen-argument fix that NO value assertion can see.

  The inline backend conversions built a fresh managed handle per call with
  PXXStrFromLit and nothing owned the result. Measured on the pre-fix compiler:
  allocs=3000 frees=0 live=3000, on x86-64 -- where every one of those calls
  printed the CORRECT string. Routing through a hidden owning local makes the
  next execution of the call site release the previous handle and scope exit
  release the last: allocs=3000 frees=2998.

  Run under tools/assert_no_leak.sh, never on its own output -- it prints OK
  either way, which is the point.
  bug-a-a-frozen-string-argument-is-empty-through-a-constructor-or-a-virtual-call-on-every-cross-backend

  THE THREE NON-VARIABLE SPELLINGS ARE HERE TOO (frankB), because each takes a
  DIFFERENT route to the conversion -- a record field carries its kind on
  ASTTk, an array element on the array SYMBOL, a function result on
  Procs[].RetType -- and each therefore materialises its own hidden owning
  temp. A variable-only loop proves ownership for one of the four.
  bug-a-a-frozen-record-field-is-refused-by-overload-resolution-against-an-ansistring-parameter }

type
  R = record f: string[10]; end;
  TArr = array[0..2] of string[10];

function Mk: string[10];
begin
  Mk := 'ret';
end;

procedure P(const a: AnsiString);
begin
  if Length(a) = 0 then WriteLn('bad: empty argument');
end;

procedure Q;
var s: string[10]; i: Integer; r: R; arr: TArr;
begin
  s := 'plain'; r.f := 'field'; arr[1] := 'elem';
  for i := 1 to 3000 do P(s);
  for i := 1 to 3000 do P(r.f);
  for i := 1 to 3000 do P(arr[1]);
  for i := 1 to 3000 do P(Mk);
end;

begin
  Q;
  WriteLn('FROZENARGLEAK OK');
end.
