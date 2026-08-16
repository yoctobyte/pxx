program test_variant_record_tag_padding;
{ Where a record's VARIANT PART starts. Every size below is FPC 3.2.2's on this
  same source.

  The variant part was always aligned to 8, so the tag field's own padding was
  charged twice: `record case k: Integer of 0: (i: Integer) end` measured 12
  where FPC says 8. The branches did overlay, so no value was ever wrong —
  what was wrong was the LAYOUT: SizeOf, the stride of an array of the record,
  and any record read from a file or handed to a C library.

  The part is now laid out from an 8-aligned base (which satisfies every
  branch) and then shifted down to the alignment the branches actually need,
  because that need is only known once they are parsed and an under-aligned
  base would move the branch fields relative to each other.
  bug-p-a-tagged-variant-record-is-padded-to-eight }

type
  TagInt   = record case k: Integer of 0: (i: Integer); 1: (b: array[0..3] of Byte); end;
  TagByte  = record case k: Byte of 0: (i: Integer); 1: (c: Char); end;
  TagWide  = record case k: Integer of 0: (a: Int64); 1: (b: array[0..7] of Byte); end;
  NoTag    = record case Integer of 0: (i: Integer); 1: (w: array[0..1] of Word); end;
  Leading  = record x: Integer; case k: Byte of 0: (i: Integer); end;
  Packed1  = packed record case k: Byte of 0: (i: Integer); 1: (c: Char); end;
  Nested   = record x: Byte; case k: Byte of
               0: (a: Byte);
               1: (case Integer of 0: (b: Int64); 1: (c: Word)); end;
  Choice   = record case Boolean of true: (x: Double); false: (y: array[0..1] of Integer); end;

var
  okc, total: Integer;
  t: TagInt;
  n: Nested;
  arr: array[0..2] of Choice;

procedure Chk(const nm: string; got, want: Integer);
begin
  Inc(total);
  if got = want then begin Inc(okc); WriteLn('ok ', nm); end
  else WriteLn('FAIL ', nm, ' got ', got, ' want ', want);
end;

begin
  okc := 0; total := 0;

  Chk('tag-int',   SizeOf(TagInt),  8);
  Chk('tag-byte',  SizeOf(TagByte), 8);
  Chk('tag-wide',  SizeOf(TagWide), 16);
  Chk('no-tag',    SizeOf(NoTag),   4);
  Chk('leading',   SizeOf(Leading), 12);
  Chk('packed',    SizeOf(Packed1), 5);
  Chk('nested',    SizeOf(Nested),  16);
  Chk('choice',    SizeOf(Choice),  8);

  { the branches still overlay, and still read back through every arm }
  t.i := $41424344;
  Chk('overlay-lo', t.b[0], $44);
  Chk('overlay-hi', t.b[3], $41);
  n.b := 7;
  Chk('nested-overlay', n.c, 7);

  { an array of such a record strides by the new size }
  arr[0].x := 1.5; arr[1].y[0] := 3; arr[2].y[1] := 9;
  Chk('array-stride-a', arr[1].y[0], 3);
  Chk('array-stride-b', arr[2].y[1], 9);
  Chk('array-size', SizeOf(arr), 24);

  WriteLn('total ok ', okc, ' / ', total);
end.
