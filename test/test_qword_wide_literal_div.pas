program test_qword_wide_literal_div;
{ A DECIMAL literal above Int64max is an UNSIGNED value.

  The lexer keeps such a literal's digit text and types the node tyInt64 with
  the wrapped 64-bit reading in ASTIVal — which is the right QWord bits and the
  wrong SIGN. Every operation that reads signedness therefore read it wrong:
  `18446744073709551615 div 5` answered 0 and `9223372036854775808 > 1`
  answered FALSE, with no diagnostic anywhere.
  bug-p-qword-div-by-a-literal-above-2-63-is-signed

  EVERY ROW BELOW WAS MEASURED AGAINST FPC 3.2.2 AND AT -O0..-O3. The rows are
  chosen so the wrong answer is never the right one: each broken row printed a
  visibly different value (0, a negative, FALSE), so this test cannot pass by
  landing on a default.

  The hex rows are a CONTROL and they are not a bug: FPC types
  $8000000000000000 as a signed Int64 too and prints the same 0 and -1, so
  those two lines must keep DIVERGING from the decimal spelling. A fix that
  "helpfully" made hex unsigned as well would break them. }
var q: qword; v: qword;
begin
  q := 18446744073709551615;
  v := 9223372036854775808;

  { --- the reported shape: a QWord dividend, a wide literal divisor --- }
  writeln(q div 9223372036854775808);          { was 0     -> 1 }
  writeln(q mod 9223372036854775808);          { was -1    -> 9223372036854775807 }
  writeln(q div 12297829382473034410);         { was 0     -> 1 }
  writeln(q mod 12297829382473034410);         { was -1    -> 6148914691236517205 }

  { --- CONSTANT-ONLY: no typed operand exists to carry the unsignedness, so
        the literal has to answer for itself. Not in the original report. --- }
  writeln(9223372036854775808 div 2);          { was -4611686018427387904 }
  writeln(9223372036854775808 mod 3);          { was -2 }
  writeln(18446744073709551615 div 5);         { was 0 }
  writeln(12297829382473034410 div 10);        { was -614891469123651720 }

  { --- COMPARISONS, which the report recorded as unaffected. They are only
        unaffected when a QWord-typed operand rescues them. --- }
  if 9223372036854775808 > 1 then writeln('gt-ok') else writeln('gt-BAD');   { was FALSE }
  if q > 9223372036854775808 then writeln('qgt-ok') else writeln('qgt-BAD'); { already ok }

  { --- CONTROLS: shapes that were already right and must stay right --- }
  writeln(q div v);                            { a VARIABLE divisor: always ok }
  writeln(q div 4611686018427387904);          { 2^62, fits Int64: always ok }
  writeln(-9223372036854775808 div 2);         { negated wide literal: stays SIGNED }
  writeln(q div $8000000000000000);            { hex: signed in FPC too }
  writeln(q mod $8000000000000000);            { hex: signed in FPC too }
  writeln(q + 0);                              { additive: never read signedness }
  writeln(q shr 63);
end.
