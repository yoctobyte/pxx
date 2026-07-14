program test_u64_to_double;
{ QWord -> Double converts as UNSIGNED: q >= 2^63 must not come out negative
  (cvtsi2sd/scvtf are signed; the unsigned fixup / ucvtf handles the top bit).
  Comparisons and field stores share the conversion, so they are covered too.
  bug-pascal-qword-to-double-signed. }
var
  q: qword; d: double;
  r: record f: double; end;
begin
  q := qword(1) shl 63;
  d := q;
  if d = 2.0*double($80000000)*double($80000000) then
    writeln('assign-ok') else writeln('assign-BAD');
  r.f := q;
  if r.f = d then writeln('field-ok') else writeln('field-BAD');
  { mixed comparison converts the qword operand the same way }
  if q = 2.0*double($80000000)*double($80000000) then
    writeln('cmp-ok') else writeln('cmp-BAD');
  { round-to-odd: 2^63+3 rounds to 2^63 as a double }
  q := q + 3;
  d := q;
  if d = 2.0*double($80000000)*double($80000000) then
    writeln('round-ok') else writeln('round-BAD');
  { small values unchanged }
  q := 12345;
  d := q;
  if d = 12345.0 then writeln('small-ok') else writeln('small-BAD');
  { signed stays signed }
  d := int64(-42);
  if d = -42.0 then writeln('signed-ok') else writeln('signed-BAD');
end.
