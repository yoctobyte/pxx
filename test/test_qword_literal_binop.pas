program test_qword_literal_binop;
{ A non-negative integer literal paired with a QWord operand joins the
  UNSIGNED domain: q + $f0000000 stays qword (the literal widens to Int64 at
  parse, and the equal-width signed-wins rule demoted the sum — correct bits,
  signed writeln/hi/compares). bug-pascal-qword-literal-binop-signed-demote. }
var q: qword;
begin
  q := $FAFAFAFA03030303;
  writeln(q + $f0000000);        { 18085043209385476867 }
  writeln(hi(q + $f0000000));    { 4210752250 }
  writeln(lo(q + 1));            { 50529028 }
  writeln($f0000000 + q);        { literal on the left too }
  if q > $f0000000 then writeln('cmp-ok') else writeln('cmp-BAD');
  { negative literal keeps the signed domain }
  if q + (-1) = q - 1 then writeln('neg-ok') else writeln('neg-BAD');
end.
