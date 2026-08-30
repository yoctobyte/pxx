{ Depth 1 and depth 2 over each of the three bases ir.inc's char-pointer
  predicate accepts: tyChar, tyUInt8, tyInt8. Nothing tested the byte and
  int8 halves at depth 2 before; `^PChar` had two tests and `^Byte` / `^ShortInt`
  had none, which is the usual shape of a gap -- the case someone hit is
  covered and its two siblings are not.

  Verified line-for-line against fpc 3.2.2, which compiles this file as-is.

  WHAT THIS FILE DOES NOT DO, stated so the next reader does not assume it:
  it does NOT pin the `PtrDepth = 1` guard in IsNodePChar's identifier arm.
  Every line here DEREFERENCES, and a deref never reaches that arm -- these
  all pass with the guard removed. The only shapes that do reach it are bare
  depth-2 identifiers in a PChar context (`WriteLn(q)`, `'x' + q`), and fpc
  REJECTS those outright, so there is no oracle to pin them against and the
  answer is a pxx dialect call rather than a conformance fact. The guard is
  held to behaviour-NEUTRALITY instead, measured as an A/B of the compiler
  built before and after the fold; see feature-a-typeref-migrate-consumers.
  feature-a-typeref-migrate-consumers }
program test_ptr_depth2_bases;
{$mode objfpc}{$H+}
type
  PPC  = ^PChar;
  PB   = ^Byte;      PPB  = ^PB;
  PI8  = ^ShortInt;  PPI8 = ^PI8;
var
  base: AnsiString; p0: PChar;    q:  PPC;
  bs: array[0..3] of Byte;     b0: PB;  qb: PPB;
  is8: array[0..3] of ShortInt; i0: PI8; qi: PPI8;
begin
  base := 'alpha'; p0 := PChar(base); q := @p0;
  bs[0] := 200;    b0 := @bs[0];      qb := @b0;
  is8[0] := -42;   i0 := @is8[0];     qi := @i0;

  { one level over each base }
  WriteLn('c1=', p0);
  WriteLn('b1=', b0^);
  WriteLn('i1=', i0^);

  { two levels over each base: one deref yields the depth-1 pointer }
  WriteLn('c2=', q^);
  WriteLn('b2=', qb^^);
  WriteLn('i2=', qi^^);

  { the depth-2 deref is the depth-1 pointer itself, not a copy of its target }
  WriteLn('ceq=', q^ = p0, ' beq=', qb^ = b0, ' ieq=', qi^ = i0);
end.
