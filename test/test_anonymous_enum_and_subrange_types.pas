{ Anonymous ENUM and anonymous SUBRANGE types, written inline wherever a type
  is expected -- `var c: (red, green, blue)`, `var n: 1..5`, a record field, an
  array element type.

  Both were "unknown type" before feature-p-anonymous-enum-and-subrange-types:
  the member-list grammar and the lo..hi grammar lived only in
  ParseTypeSection's NAMING path, so the same construct worked with a name in
  front of it and not without. ParseTypeKind already had anonymous arms for
  record, procedural, pointer, array and set -- these were the two missing.

  Expected values are fpc 3.2.2 -Mobjfpc -O1's, with one documented exception
  noted at the SizeOf row. }
program test_anonymous_enum_and_subrange_types;

type
  TRec = record
    f: (ra, rb, rc);      { anonymous enum as a field type }
    g: 1..9;              { anonymous subrange as a field type }
  end;

var
  c: (red, green, blue);
  holes: (hx = 10, hy, hz = 20);   { explicit ordinals must work here too }
  n: 1..5;
  neg: -3..3;
  ch: 'a'..'e';
  a: array[0..2] of 1..9;          { anonymous subrange as an ELEMENT type }
  ae: array[0..1] of (ea, eb);     { anonymous enum as an ELEMENT type }
  r: TRec;
  i, trips, fails: Integer;

procedure Chk(const nm: string; got, want: Int64);
begin
  if got = want then WriteLn(nm, ' ok')
  else begin WriteLn(nm, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

begin
  fails := 0;

  { anonymous enum: value, ordering, and the bounds Low/High report }
  c := green;
  Chk('enum.val', Ord(c), 1);
  Chk('enum.low', Ord(Low(c)), 0);
  Chk('enum.high', Ord(High(c)), 2);
  if c = green then WriteLn('enum.cmp ok')
  else begin WriteLn('enum.cmp FAIL'); Inc(fails); end;
  c := blue;
  Chk('enum.reassign', Ord(c), 2);

  { explicit ordinals and the holes they create }
  holes := hz;
  Chk('holes.z', Ord(holes), 20);
  Chk('holes.y', Ord(hy), 11);
  Chk('holes.x', Ord(hx), 10);

  { anonymous integer subrange: value and its OWN bounds, not the base type's }
  n := 3;
  Chk('sub.val', n, 3);
  Chk('sub.low', Low(n), 1);
  Chk('sub.high', High(n), 5);
  neg := -2;
  Chk('subneg.val', neg, -2);
  Chk('subneg.low', Low(neg), -3);
  Chk('subneg.high', High(neg), 3);

  { anonymous CHAR subrange -- the base type must come out Char, not Integer }
  ch := 'c';
  Chk('subchar.ord', Ord(ch), 99);
  Chk('subchar.low', Ord(Low(ch)), 97);
  Chk('subchar.high', Ord(High(ch)), 101);
  if (Low(ch) = 'a') and (High(ch) = 'e') then WriteLn('subchar.istype ok')
  else begin WriteLn('subchar.istype FAIL'); Inc(fails); end;

  { as record FIELD types }
  r.f := rb; r.g := 4;
  Chk('field.enum', Ord(r.f), 1);
  Chk('field.sub', r.g, 4);

  { as array ELEMENT types }
  a[0] := 7; a[2] := 9;
  Chk('elem.sub', a[0] + a[2], 16);
  ae[0] := eb;
  Chk('elem.enum', Ord(ae[0]), 1);

  { the loop that motivates retaining the bounds at all }
  trips := 0;
  for i := Low(n) to High(n) do Inc(trips);
  Chk('loop.trips', trips, 5);

  { SizeOf of a subrange is 4 here and 1 in fpc -- our subranges are stored at
    the base type's width. compat-pascal-subrange-storage-size, unrelated to
    this ticket; asserted at the pxx value so a change to THAT rule shows up
    here rather than drifting. }
  Chk('sub.sizeof-dialect', SizeOf(n), 4);
  Chk('enum.sizeof', SizeOf(c), 4);

  if fails = 0 then WriteLn('ALL OK') else WriteLn('FAILURES ', fails);
end.
