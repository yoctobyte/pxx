{ A WideChar or UCS4Char stored into a Variant.

  Both were refused outright -- `Variant := this type not yet supported` --
  while every neighbouring kind (Char, ShortString, Single, Currency) was
  accepted. They were the entire "fpc accepts, pxx refuses" set in a 625-pair
  assignment cross-product, alongside the interface case which is a separate
  ticket.

  The obvious route is the wrong one. The variant's only character slot is
  VT_CHAR, whose payload is ONE BYTE (defs.inc), so adding tyWideChar and
  tyUCS4Char to the store's tag table would truncate every character outside
  Latin-1: `v := WideChar($20AC)` would come back as #$AC, trading a refusal
  for a silently wrong value. Instead the value converts to its UTF-8 STRING
  first -- the same conversion every other string context already applies to
  these two kinds -- and the store then sees an ordinary tyAnsiString.

  So the rows that matter are the ones OUTSIDE Latin-1 and outside the BMP:
  those are what a byte-wide slot would have destroyed. `v := someWord` is
  pinned too, because the string-assignment arm identifies a widechar by its
  tyUInt16 storage, and reusing that heuristic here would have turned every
  Word stored in a Variant into a character.
  ORACLE, stated exactly: fpc 3.2.2's ACCEPTANCE of all three source types is
  measured (the cross-product above, 2026-08-24). Its printed OUTPUT is not
  available on this box -- `uses Variants` cannot be resolved here even with
  -Fu pointed at a present, version-correct variants.ppu, so no fpc binary that
  prints a Variant can be built to diff against. The expected values below
  therefore come from pxx's own documented rule for these two kinds ("converts
  as UTF-8", defs.inc), which is the rule every other string context in the
  dialect already applies to them -- not from an fpc run.
  bug-p-a-variant-refuses-wide-chars-and-interfaces }
program test_variant_widechar_store;
{$mode objfpc}{$H+}
type
  TR = record v: Variant; end;
procedure P(v: Variant);
begin
  WriteLn('param [', v, ']');
end;
var
  v: Variant; wc: WideChar; u: UCS4Char; c: Char; w: Word; i: Integer;
  r: TR; a: array[0..1] of Variant;
begin
  { the neighbouring kind that always worked, as the control }
  c := 'A'; v := c; WriteLn('char [', v, ']');

  { WideChar: ASCII, Latin-1, and a BMP character a byte slot would truncate }
  wc := WideChar(Ord('B')); v := wc; WriteLn('wc-ascii [', v, ']');
  wc := WideChar($00E9);    v := wc; WriteLn('wc-e9 [', v, ']');
  wc := WideChar($20AC);    v := wc; WriteLn('wc-euro [', v, ']');

  { UCS4Char: the same, plus a code point outside the BMP }
  u := UCS4Char(Ord('C')); v := u; WriteLn('u-ascii [', v, ']');
  u := UCS4Char($00E9);    v := u; WriteLn('u-e9 [', v, ']');
  u := UCS4Char($20AC);    v := u; WriteLn('u-euro [', v, ']');
  u := UCS4Char($1F600);   v := u; WriteLn('u-emoji [', v, ']');

  { NOT characters: a Word and an Integer must still be NUMBERS }
  w := 300; v := w; WriteLn('word [', v, ']');
  w := 65;  v := w; WriteLn('word65 [', v, ']');
  i := -42; v := i; WriteLn('int [', v, ']');

  { the same store reached as a record field, an array element, and an argument }
  wc := WideChar($20AC);
  r.v := wc;  WriteLn('field [', r.v, ']');
  a[0] := wc; WriteLn('elem [', a[0], ']');
  P(wc);

  { a cast expression, not just a variable read }
  v := WideChar($00FC); WriteLn('cast [', v, ']');

  { and the value is a real string in the slot, so string things work on it }
  wc := WideChar($20AC); v := wc;
  WriteLn('concat [', v + '!', ']');
end.
