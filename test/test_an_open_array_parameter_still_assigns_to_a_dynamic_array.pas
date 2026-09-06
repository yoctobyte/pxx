{ THE POSITIVE CONTROL for test_a_static_array_is_not_a_dynamic_array_fail, and
  it is drawn from the population that guard is about: an array source assigned
  to a dynamic array, which must still be ACCEPTED when the source is an
  open-array parameter.

  It is not hypothetical. The first version of that guard tested `ArrLen > 0`
  and refused this file, because AllocParam stamps `ArrLen := 1000` on EVERY
  array parameter as the open-array placeholder -- so `ArrLen` does not mean
  "fixed length" and a guard reading it that way is wrong for every parameter.
  `Kind <> skParam` is what actually separates them.

  NO FPC ORACLE FOR THIS FILE, DELIBERATELY. fpc 3.2.2 REFUSES `t := o` here
  ("Incompatible types: got {Open} Array Of LongInt expected TA"), so these
  values are ours and cannot be generated from it. Us accepting what fpc rejects
  is not a defect (CLAUDE.md), and the reason it works is worth recording: the
  open-array marshalling temp already carries [len:8][data], which is exactly
  the header a dynamic array's handle slot wants -- which is also the route the
  static-array COPY should take rather than a new ABI.

  The dyn-to-dyn row is here as the other thing the guard must not touch, and
  that one fpc does accept. }
program test_an_open_array_parameter_still_assigns_to_a_dynamic_array;
type TA = array of LongInt;
var d, e: TA;

procedure FromOpen(const o: array of LongInt);
var t: TA;
    k: LongInt;
begin
  t := o;
  Write('open->dyn len=', Length(t), ':');
  for k := 0 to High(t) do Write(' ', t[k]);
  Writeln;
end;

var s: array[0..2] of LongInt;
begin
  s[0] := 2; s[1] := 4; s[2] := 6;
  e := TA.Create(11, 22);
  d := e;
  Write('dyn->dyn  len=', Length(d), ':');
  Write(' ', d[0], ' ', d[1]);
  Writeln;
  FromOpen(s);
end.
