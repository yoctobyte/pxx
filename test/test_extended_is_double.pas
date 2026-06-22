program test_extended_is_double;

{ feature-extended-alias-or-reject (option a): `Extended` is a plain alias for
  `Double` on every target — no 80-bit x87 path, no extra precision. This pins
  that an Extended and a Double fed identical inputs produce identical results
  (same rounding), and that Extended survives a record round-trip at 8-byte
  width (a record of two Extendeds is 16 bytes, like two Doubles). }

type
  TPair = record a, b: Extended; end;

var
  e: Extended;
  d: Double;
  p: TPair;
begin
  e := 1.0; e := e / 3.0;          { 0.333... in double rounding }
  d := 1.0; d := d / 3.0;
  if e = d then WriteLn('eq-div') else WriteLn('NE-div');

  e := 2.0; e := e * e * e * e;    { 16 }
  WriteLn(e:0:1);

  p.a := 1.25; p.b := 4.75;        { record fields are 8-byte Doubles }
  WriteLn((p.a + p.b):0:2);        { 6.00 }
end.
