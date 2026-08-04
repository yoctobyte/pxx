{ PromoInt in PASCAL: `shr`, and a value cast to a machine integer.
  bug-a-promoint-shr-yields-nothing-and-a-machine-int-cast-yields-the-slot-address

  Both defects were the SAME confusion — a promotable int's rvalue is its SLOT
  ADDRESS — surfacing in two places that never demoted it:

  * `shr` is lexed as an IDENTIFIER in Pascal (there is no tkShr token for it;
    the term parser stores Ord(tkIdent)), so PromoOpHelper did not recognise it,
    the promo branch declined the node, and the generic integer path shifted two
    POINTERS. `shl` has a real token and was always correct, which is why this
    read as a one-operator bug.

  * every `T(n)` value cast punned the address. Three separate parser sites
    reach these casts — the keyword tokens (Integer/Byte/LongWord), the
    ident-spelled ordinal names (Int64/LongInt/Cardinal/Word/...), and
    Char/Boolean — so fixing one made Integer(n) right while Int64(n) stayed
    wrong.

  `Pointer(n)` is deliberately NOT demoted: on a promotable int that spelling IS
  its slot address, and it is how PXXPromoToStr is reached from Pascal source. }
program t;
uses promocore;
var n, d, big: PromoInt;
begin
  { shr at several widths, checked against the div-by-power-of-two answer }
  n := 255;
  d := n shr 1;  writeln(d, ' ', n div 2);
  d := n shr 4;  writeln(d, ' ', n div 16);
  d := n shl 1;  writeln(d);
  { a value that has SPILLED to the heap tier, shifted back down }
  big := 1;
  big := big shl 70;
  writeln(big);
  writeln(big shr 70);
  writeln(big shr 65);

  { every cast spelling, all of which used to yield the slot address }
  n := 12;
  writeln(Integer(n), ' ', LongInt(n), ' ', Int64(n), ' ', NativeInt(n));
  writeln(Cardinal(n), ' ', LongWord(n), ' ', Word(n), ' ', Byte(n));
  writeln(SmallInt(n), ' ', QWord(n));
  n := 65;
  writeln(Char(n));
  n := 0;
  writeln(Boolean(n));
  n := 12;
  writeln(Boolean(n));

  { ...and Pointer(n) still reaches the runtime, unchanged }
  n := 1; n := n * 70000000000;
  writeln(PXXPromoToStr(@n));
  writeln(PXXPromoToStr(Pointer(n)));
end.
