{ `v := Variant(y)` for `y: LongInt` SEGFAULTED at run time, while `v := y` on
  the line above it printed 233. One spelling of a conversion crashing while the
  other -- which does strictly more work -- is fine: the tell that the cast was
  not doing the conversion at all.

  The cast door built an AN_PTR_CAST that retagged the integer AS a variant
  record, so the assignment saw a right-hand side already typed tyVariant,
  skipped the boxing it does for the implicit form, and copied 16 bytes of
  whatever sat beside a 4-byte local. `Variant(x)` is now the same BOXING
  conversion the implicit assignment performs: yield the operand and let the
  assignment box it.

  An operand that is ALREADY a variant keeps the cast node, so `Variant(v)`
  stays the identity it was and OleVariant does not become a second path.

  THE ROUNDTRIP ROWS ARE THE POINT, not the print rows: a pun and a conversion
  both "work" when you only print the variant, because Write of a variant reads
  the tag it was handed. Casting back out is what asks whether the tag and the
  payload agree.

  The `v := y` rows are the CONTROL -- the implicit spelling, which never
  crashed -- so a regression in the boxing itself moves both columns rather than
  one. .expected is fpc 3.2.2's own output. }
program test_a_cast_to_variant_boxes_instead_of_punning;
{$mode delphi}
var
  v, w: Variant;
  ov: OleVariant;
  y: LongInt;
  d: Double;
  c: Char;
  b: Boolean;
  s: string;
  back: LongInt;
  dback: Double;
  sback: string;
begin
  y := 233; d := 1.5; c := 'q'; b := True; s := 'abc';

  v := Variant(y);    WriteLn('cast   int    ', v);
  v := y;             WriteLn('assign int    ', v);
  v := Variant(d);    WriteLn('cast   double ', v);
  v := Variant(c);    WriteLn('cast   char   ', v);
  v := Variant(b);    WriteLn('cast   bool   ', v);
  v := Variant(s);    WriteLn('cast   string ', v);
  ov := OleVariant(y); WriteLn('cast   ole    ', ov);

  { the identity: an operand that is already a variant }
  v := Variant(y);
  w := Variant(v);    WriteLn('cast   variant', ' ', w);

  { the roundtrips -- tag and payload must agree, which a pun cannot manage }
  v := Variant(y);    back  := Integer(v);   WriteLn('round  int    ', back);
  v := Variant(d);    dback := Double(v);    WriteLn('round  double ', dback:0:2);
  v := Variant(s);    sback := string(v);    WriteLn('round  string ', sback);

  WriteLn('inline        ', Variant(y));
  { AND THE EXPRESSION HAS A TYPE. Yielding the operand so the assignment boxes
    it left `Variant(y)` with the OPERAND's static type, and SizeOf reads the
    node's tk -- so `SizeOf(Variant(y))` answered a scalar width while
    `SizeOf(v)` answered 16, which is what
    regression-test-core-test-builtin-type-names-cast-and-declare caught one
    file away. Asserted as a RELATION between two of our own answers, so it
    carries no platform width and is true wherever a Variant is whatever it is
    here. The row belongs in THIS file too: the builtin-names file found it, but
    the behaviour is the Variant cast's. }
  WriteLn('sizeof same   ', SizeOf(Variant(y)) = SizeOf(v));
  WriteLn('VARIANT CAST OK');
end.
