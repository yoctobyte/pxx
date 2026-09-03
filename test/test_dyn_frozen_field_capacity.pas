program test_dyn_frozen_field_capacity;
{ A dynamic-array FIELD whose element is a frozen `string[N]` must take its
  per-element capacity from the ELEMENT'S OWN DECLARATION -- in every spelling,
  in a record and in a class alike.

  It took it from nowhere. The field parsers test `fIsDyn` FIRST, and that arm
  returns before the frozen-field arm that is the only place `fStrCap` is ever
  assigned, so a dynamic-array field kept whatever the PREVIOUS field in the
  same type had left in the variable. Two faces, opposite signs:

    - with a frozen field in front of it, the capacity was that NEIGHBOUR'S
      (`pad: string[3]` made a `string[10]` element clamp at 3) -- silent
      truncation, and a value that changes when an unrelated declaration moves;
    - with no frozen field in front of it, the leftover was 0, which the store
      path reads as "no limit", so a 26-character value went whole into a
      10-character element and OVERRAN it.

  The overrun is why this is a crash and not only wrong text. The allocation
  and the store take the stride from different places, and while BOTH were
  wrong-and-small the malloc bucket absorbed the difference; the moment one of
  them tells the truth the other one runs off the block. In the default mode
  `SetLength(r.row,1); r.row[0] := <26 chars>` over `array of string[20]` then
  SIGSEGVs at the NEXT allocation -- two statements after the cause.

  So the ORDER and NOCLAMP rows are the point of this file: the first fails if
  the capacity is read from a neighbour, the second if it is not read at all.
  MULTI exists because a several-element row is what a pointer-wide allocation
  stride corrupts; one element per row cannot see it.
  bug-a-a-frozen-dynamic-array-field-records-a-junk-element-capacity }
type
  TS10 = string[10];
  TDyn = array of TS10;
  RInline = record row: array of string[10]; end;      { inline dyn, inline element }
  RAlias  = record row: array of TS10; end;            { inline dyn, named element }
  RNamed  = record row: TDyn; end;                     { named dyn type }
  ROrder  = record pad: string[3]; row: array of string[10]; end;
  CFirst  = class row: array of string[10]; end;       { nothing frozen in front }
  COrder  = class pad: string[3]; row: array of TS10; end;
var
  ri: RInline; ra: RAlias; rn: RNamed; ro: ROrder;
  cf: CFirst; co: COrder;
  tail: array of string[10];
  i: Integer;
const
  LONG = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';   { 26 chars, over every capacity here }

begin
  { MULTI -- four elements per row, in all three record spellings and in a
    class. A pointer-wide allocation stride overlaps them; the first row of
    each pair is the one that showed `<row0xxx` followed by a neighbour's
    length byte. }
  cf := CFirst.Create;
  SetLength(ri.row, 4); SetLength(ra.row, 4); SetLength(rn.row, 4);
  SetLength(cf.row, 4);
  for i := 0 to 3 do
  begin
    ri.row[i] := 'inl' + Chr(48 + i) + 'xxxxx';
    ra.row[i] := 'als' + Chr(48 + i) + 'yyyyy';
    rn.row[i] := 'nam' + Chr(48 + i) + 'zzzzz';
    cf.row[i] := 'cls' + Chr(48 + i) + 'wwwww';
  end;
  Write('INLINE '); for i := 0 to 3 do Write('<', ri.row[i], '>'); WriteLn;
  Write('ALIAS  '); for i := 0 to 3 do Write('<', ra.row[i], '>'); WriteLn;
  Write('NAMED  '); for i := 0 to 3 do Write('<', rn.row[i], '>'); WriteLn;
  Write('CLASS  '); for i := 0 to 3 do Write('<', cf.row[i], '>'); WriteLn;

  { ORDER -- the element declares 10 and the field in front declares 3. Both
    rows must be the element's 10. A 3 here is the neighbour leaking in. }
  ro.pad := 'pad';
  SetLength(ro.row, 2);
  ro.row[0] := '0123456789'; ro.row[1] := 'abcdefghij';
  co := COrder.Create;
  co.pad := 'pad';
  SetLength(co.row, 2);
  co.row[0] := '0123456789'; co.row[1] := 'abcdefghij';
  WriteLn('ORDER  <', ro.row[0], '><', ro.row[1], '><', co.row[0], '><', co.row[1], '>');
  WriteLn('PAD    <', ro.pad, '><', co.pad, '>');

  { NOCLAMP -- 26 characters into a 10-character element. Must be cut to 10;
    anything longer is a write past the element. }
  cf.row[0] := LONG;
  ri.row[0] := LONG;
  WriteLn('CLAMP  <', ri.row[0], '><', cf.row[0], '>');

  { The allocation that used to take the SIGSEGV. It must both succeed and
    round-trip, because a survived overrun leaves the heap plausible. }
  SetLength(tail, 3);
  for i := 0 to 2 do tail[i] := 'tail' + Chr(48 + i);
  WriteLn('TAIL   <', tail[0], '><', tail[1], '><', tail[2], '>');
end.
