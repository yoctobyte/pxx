program test_record_cast_field_offset;
{ Value-typecast of a variable to a record type accesses fields IN PLACE at
  @var + field offset (FPC semantics): `tqwordrec(q).high` reads/writes the
  high dword. Previously every field resolved at offset 0, silently (rvalue,
  lvalue, and nested alike). Also: `not (q or q)` on qwords is a bitwise
  complement, not a boolean flip (same tint642 burn-down).
  bug-pascal-record-cast-field-offset. }
type
  tinner = packed record x, y: word; end;
  touter = packed record a: cardinal; inr: tinner; end;  { 8 bytes }
  tqwordrec = packed record low, high: cardinal; end;
var q, o, m1, m2: qword;
begin
  q := 0;
  tqwordrec(q).high := $12345678;
  tqwordrec(q).low := $9ABCDEF0;
  writeln(tqwordrec(q).high);          { 305419896 }
  writeln(tqwordrec(q).low);           { 2596069104 }
  writeln(q);                          { 1311768467463790320 }
  o := 0;
  touter(o).inr.y := 5;                { nested: offset 6 }
  writeln(o shr 48);                   { 5 }
  writeln(touter(o).inr.y);            { 5 }
  { not over a sized-type or/and is bitwise }
  m1 := qword($F0F0F0F0) or (qword($F0F0F0F0) shl 32);
  m2 := qword($0F0F0F0F) or (qword($0F0F0F0F) shl 32);
  if not(m1) = m2 then writeln('not-ok') else writeln('not-BAD');
  if not(m1 or m2) = qword(0) then writeln('notor-ok') else writeln('notor-BAD');
end.
