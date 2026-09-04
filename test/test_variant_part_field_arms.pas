program test_variant_part_field_arms;
{ A variant record's BRANCH fields are parsed by a THIRD copy of the field
  declaration parser, and it was missing two arms the other two have had for
  months.

  refactor-p-the-field-declaration-parser-exists-twice names two copies --
  ParseRecordFields and ParseTypeSection's class arm. There are three:
  ParseRecordVariantPart is the one nobody counted, and its own comments already
  said so in both directions ("exactly as the FIXED part of the record does it a
  few hundred lines down"; "the variant-part arm a few hundred lines up already
  tested both kinds, this one and its class sibling did not"). The drift goes
  both ways, which is the refactor's whole argument.

  WHAT WAS MISSING, both silent, both measured on pin v403:

  1. the ENUM identity stamp. `case Integer of 0: (c: TColor)` printed the
     ORDINAL -- `2` for Blue -- where the same field in the fixed part and in a
     class printed `Blue`. FPC prints Blue in all three.
     bug-p-an-enum-reached-through-a-field-or-index-still-writes-its-ordinal

  2. any arm at all for a NAMED array type. ParseTypeKind answers the ELEMENT
     kind for such a name, so `0: (a: TArr)` with `TArr = array[0..3] of
     Integer` sized the whole record at EIGHT bytes where FPC says 20, and
     `v.a[3] := 44` wrote twelve bytes past its end. It read back correctly,
     because the read went to the same wrong place.

  THE SIZEOF ROW IS THE ONE THAT CANNOT PASS BY ACCIDENT. The value rows all
  printed plausible numbers on the pin -- 11 and 44 came back exactly as
  written -- because an out-of-bounds write and its matching read agree. Only
  the size says the record was too small. Pin v403 prints:
      branch 2 11 44 / enumarr 0 2 / sizeof 8
  against 20 here and in FPC.

  A dynamic array in a branch is deliberately NOT covered: FPC refuses any
  reference-counted type in a variant part and so does pxx, so the missing arm
  for those is correct. A multi-dimensional NAMED array is refused with a
  message rather than mis-sized, which makes it agree with the inline
  `array[0..1, 0..2]` spelling that was already refused one message earlier. }
{$MODE OBJFPC}
type
  TColor = (Red, Green, Blue);
  TArr   = array[0..3] of Integer;
  TLoArr = array[2..4] of SmallInt;      { a non-zero low bound }
  TEArr  = array[0..2] of TColor;        { an array OF the enum }
  TFixed = record c: TColor; a: TArr; end;   { the copy that already worked }
  TVar = record
    case Integer of
      0: (c: TColor; a: TArr);
      1: (n: Integer);
      2: (lo: TLoArr);
      3: (ea: TEArr);
      4: (s: string[7]);                 { the arm a previous fix added here }
  end;
var f: TFixed; v: TVar;
begin
  f.c := Green; f.a[3] := 9;
  WriteLn('fixed  ', f.c, ' ', f.a[3], ' ', SizeOf(TFixed));
  v.c := Blue; v.a[0] := 11; v.a[3] := 44;
  WriteLn('branch ', v.c, ' ', v.a[0], ' ', v.a[3]);
  v.lo[2] := 5; v.lo[4] := 7;
  WriteLn('lobnd  ', v.lo[2], ' ', v.lo[4]);
  v.ea[0] := Red; v.ea[2] := Blue;
  WriteLn('enumarr', ' ', v.ea[0], ' ', v.ea[2]);
  v.s := 'abcdefg';
  WriteLn('str    ', v.s);
  WriteLn('sizeof ', SizeOf(TVar));
end.
