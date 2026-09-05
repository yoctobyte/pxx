{ `packed array[..] of T` as a FIELD, in a record body and in a class body.

  These were two copies of one field-declaration parser, and only the record
  copy skipped a `packed` that precedes `array` -- so fcl-fpcunit's own spelling
  (`entries: packed array[0..0] of TRec`) compiled as a record field and was
  `expected 'record' before 'array'` as a class field. A field-level feature
  present on one declaring kind and absent on the other, which reads as a
  dialect gap rather than as a missing paste. fpc 3.2.2 takes both.

  `packed` on an ARRAY only affects ELEMENT padding, and pxx already lays array
  elements out contiguously, so the accepted spelling must parse EXACTLY as the
  unpacked one. That is what this file asserts and it is the whole point of the
  pairing: every packed row has an unpacked twin of the same shape, and the two
  must agree on the value written through the field AND on SizeOf. A parser that
  accepted the word `packed` and then took a different layout path would compile
  every line here and fail those pairs -- so "it compiles" is not what is being
  checked.

  THE THIRD DECLARING KIND IS DELIBERATELY ABSENT AND IT IS STILL BROKEN: a
  variant branch (`1: (e: packed array[0..1] of TCell)`) is refused today, and
  fpc accepts it. ParseRecordVariantPart is a THIRD copy of this parser and has
  not been merged, because merging it is not a paste -- its branch bookkeeping
  is single-dimension and its refusal of reference-counted types is CORRECT and
  specific to variant parts, so both would have to become parameters. Left out
  rather than left unmentioned, so nobody reads a green here as covering it.
  test_packed_array_field_in_a_variant_branch.pas is where that lands.
  refactor-p-the-field-declaration-parser-exists-twice }
program test_packed_array_field_in_a_record_and_a_class;
{$mode objfpc}{$H+}

type
  TCell = record a, b: Integer; end;

  TRecPacked   = record e: packed array[0..1] of TCell; end;
  TRecUnpacked = record e:        array[0..1] of TCell; end;

  TClsPacked = class
    e: packed array[0..1] of TCell;
  end;
  TClsUnpacked = class
    e:        array[0..1] of TCell;
  end;

var
  rp: TRecPacked;   ru: TRecUnpacked;
  cp: TClsPacked;   cu: TClsUnpacked;

begin
  rp.e[1].a := 11;  ru.e[1].a := 11;
  WriteLn(rp.e[1].a, ' ', ru.e[1].a, ' ', SizeOf(TRecPacked), ' ', SizeOf(TRecUnpacked));

  cp := TClsPacked.Create;   cu := TClsUnpacked.Create;
  cp.e[1].a := 22;  cu.e[1].a := 22;
  WriteLn(cp.e[1].a, ' ', cu.e[1].a);

  { the packed and unpacked class instances must also be the same SIZE -- the
    value rows above pass whether or not `packed` changed the layout }
  WriteLn(TClsPacked.InstanceSize = TClsUnpacked.InstanceSize);
end.
