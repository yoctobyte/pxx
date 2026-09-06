{ A DECIMAL integer literal between High(Int64) and High(QWord) is a QWord, in
  the expression path AND in the const evaluator. It used to be neither: written
  inline it did not COMPILE at all (routed to the promotable-int path, "runtime
  helper PXXPromoFromStr not found"), and written as a const it compiled and
  printed the wrapped SIGNED reading -- 14695981039346656037, the FNV-1a offset
  basis, came out as -3750763034362895579.

  DO NOT DECLARE A PromoInt IN THIS FILE. It has none on purpose: that is what
  keeps promocore unloaded, and it is the only reason this file can catch a
  predicate WIDENED to route the [2^63, 2^64) band through the promo runtime --
  which shows up here as a compile failure and is invisible anywhere promocore
  is loaded. Its sibling test_promoint_bitwise.pas catches the opposite
  direction (narrowed -> PromoInt reads the wrapped value); the two are the two
  arms of one tag and each is the other's positive control. Adding a PromoInt
  here would silently disarm this half.

  A HEX literal is the control that must NOT move: fpc types $8000000000000063
  by its bit width, so it is negative in both compilers, and the lexer records a
  digit span for decimal only. The small rows are the second control -- nothing
  under High(Int64) may change type. }
{$mode objfpc}
program test_a_decimal_literal_above_high_int64_is_a_qword;
const
  C   = 9223372036854775907;          { High(Int64) + 100 }
  FNV = 14695981039346656037;         { FNV-1a 64-bit offset basis }
  MAXQ = 18446744073709551615;        { High(QWord) }
  BOUND = 9223372036854775807;        { High(Int64) itself -- still signed }
  OVER  = 9223372036854775808;        { High(Int64) + 1 -- the first QWord }
  HEXD = $8000000000000063;           { same bits as C, and fpc says negative }
  HALF = 18446744073709551615 div 2;
var q: QWord; i: Int64;
begin
  Writeln('inline   = ', 9223372036854775907);
  Writeln('inline f = ', 14695981039346656037);
  if 9223372036854775907 > 0 then Writeln('inline cmp: positive')
                             else Writeln('inline cmp: negative');
  Writeln('C        = ', C);
  Writeln('FNV      = ', FNV);
  Writeln('MAXQ     = ', MAXQ);
  Writeln('BOUND    = ', BOUND);
  Writeln('OVER     = ', OVER);
  Writeln('HALF     = ', HALF);
  if C > 0 then Writeln('C cmp    : positive') else Writeln('C cmp    : negative');
  Writeln('HEXD     = ', HEXD);
  if HEXD > 0 then Writeln('HEXD cmp : positive') else Writeln('HEXD cmp : negative');
  q := 9223372036854775907;  Writeln('q        = ', q);
  i := -9223372036854775708; Writeln('i        = ', i);
  Writeln('sizeof   = ', SizeOf(C), ' ', SizeOf(BOUND));
  Writeln('small    = ', 12345, ' ', -12345, ' ', 4294967296, ' ', -4294967296);
end.
