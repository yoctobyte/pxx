{ A `string[N]` field in the VARIANT part of a record.

  The variant-part field builder (ParseRecordVariantPart) had no frozen-string
  arm at all, while the FIXED part a few hundred lines away has one. So a
  `string[N]` branch was:

  * sized `TypeSize(tyFixedString)` = 8 bytes instead of its slot size, which
    UNDERSIZED the whole record — `record id: Integer; case k of ...
    (s: string[40]) end` measured 16 bytes where the field alone needs 48, so
    writing it ran past the end of the record; and
  * registered as `tyFixedString` rather than `tyString` + `UFldStrCap`, which
    is how the fixed part spells it — so reading the field back yielded an
    ADDRESS. `WriteLn(v.s)` printed a number.

  Both silent. Every other variant-branch type was already correct — Integer,
  Double, Char, Boolean, a fixed array, a nested record — which is exactly why
  this survived: the one type that needed a second code path was the one that
  did not get it.

  All rows diffed against FPC. SIZES are deliberately not asserted against FPC:
  pxx's frozen string is [len:8][chars:N] and FPC's is [len:1][chars:N], so the
  numbers legitimately differ. What must hold is that the variant spelling and
  the plain spelling agree with EACH OTHER.
  bug-a-a-frozen-string-field-in-a-variant-part-is-8-bytes-and-untyped }
program test_variant_part_string_field;
type
  TKind = (kInt, kStr, kPair);
  TVar = record
    id: Integer;
    case k: TKind of
      kInt:  (iv: Integer);
      kStr:  (sv: string[6]);
      kPair: (a, b: SmallInt);
  end;
  TPlain = record id: Integer; sv: string[6]; end;

  { the size control: same field, the two spellings }
  TVSize = record id: Integer; case k: TKind of kInt: (i: Integer); kStr: (s: string[40]); end;
  TPSize = record id: Integer; s: string[40]; end;

var
  v: TVar; p: TPlain;
  av: array[0..1] of TVar;
begin
  v.id := 1; v.sv := 'aa';
  WriteLn('scalar  ', v.id, ' ', v.sv, ' ', Length(v.sv));
  p.id := 2; p.sv := 'bb';
  WriteLn('plain   ', p.id, ' ', p.sv, ' ', Length(p.sv));

  av[0].sv := 'cc';
  WriteLn('element ', av[0].sv);
  with av[1] do sv := 'ee';
  WriteLn('with    ', av[1].sv);

  { truncation at the declared capacity, like any string[6] }
  v.sv := 'abcdefghij';
  WriteLn('trunc   ', v.sv, ' ', Length(v.sv));

  { the overlay still overlays: writing the other branch changes these bytes }
  v.iv := 0;
  WriteLn('overlay ', Length(v.sv));

  { the UNDERSIZE, stated behaviourally: filling element 0's string to capacity
    must not reach element 1. With the field sized 8 bytes it did. SizeOf itself
    is not asserted — pxx's [len:8][chars:N] and FPC's [len:1][chars:N] give
    different numbers for the same correct layout. }
  av[0].id := 11; av[1].id := 22;
  av[0].sv := 'abcdef';
  WriteLn('no ovr  ', av[1].id, ' ', av[0].sv);
  WriteLn('VARIANT PART STRING FIELD OK');
end.
