{ A value typecast through a RECORD ALIAS, then `.field` / `.method`:
  `R2(v).a` was refused ("expected ')' before '.'") while `TR(v).a` compiled.
  And TDoubleRec reached from a unit (tdoublerec_alias_unit). Output = fpc 3.2.2.
  feature-b-rtl-has-no-tdoublerec }
program test_tdoublerec_alias_cast;
{$mode objfpc}{$modeswitch advancedrecords}
uses tdoublerec_alias_unit;
type
  TR = record a: LongInt; function F: LongInt; end;
  R2 = TR;
function TR.F: LongInt; begin Result := a * 2; end;
type TPair = record lo, hi: LongWord; end;
  TB4 = packed record b0, b1, b2, b3: Byte; end;
var v: LongInt; z: Double; q: Int64; w: LongWord; pr: TPair; b4: TB4;
begin
  v := 21;
  writeln(TR(v).F, ' ', R2(v).a, ' ', R2(v).F);
  z := 0;
  writeln(IsFiniteNonZero(2.5), ' ', IsFiniteNonZero(z), ' ', IsFiniteNonZero(-1e-300));
  writeln(MantissaOf(1.5), ' ', MantissaOf(z));
  { a bare whole-value cast of a SCALAR to a record reinterprets its bytes:
    it read a record from the address the bits spelled, and segfaulted }
  z := 1.5; pr := TPair(z); writeln(pr.hi);
  q := -1; pr := TPair(q); writeln(pr.lo, ' ', pr.hi);
  w := $04030201; b4 := TB4(w); writeln(b4.b0, ' ', b4.b3);
end.
