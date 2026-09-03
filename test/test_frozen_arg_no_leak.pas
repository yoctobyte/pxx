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
  bug-a-a-frozen-string-argument-is-empty-through-a-constructor-or-a-virtual-call-on-every-cross-backend }

procedure P(const a: AnsiString);
begin
  if Length(a) = 0 then WriteLn('bad: empty argument');
end;

procedure Q;
var s: string[10]; i: Integer;
begin
  s := 'plain';
  for i := 1 to 3000 do P(s);
end;

begin
  Q;
  WriteLn('FROZENARGLEAK OK');
end.
