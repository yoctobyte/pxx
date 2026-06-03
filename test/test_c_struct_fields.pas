{ C struct field access (axis 3) and typed pointer fields (axis 2). The
  imported test header test/cstructs.h declares two typedef structs with a
  body; the importer lays them out as real records with C natural alignment
  instead of opaque pointers. Exercises: scalar fields, a nested struct by
  value (Item.origin: Point), and a `char *` field that carries its element
  type so it is indexable as a C string. }
program test_c_struct_fields;
uses cstructs;
var
  p: Point;
  it: Item;
  s: string;
  q: PPoint;
begin
  p.x := 3;
  p.y := 4;
  writeln(p.x + p.y);                   { 7 }

  it.id := 9;
  it.origin.x := 5;
  it.origin.y := 6;
  writeln(it.id);                       { 9 }
  writeln(it.origin.x + it.origin.y);   { 11 — nested struct by value }

  s := 'hi';
  it.name := PChar(s);                  { char* field is a typed char pointer }
  writeln(it.name[0]);                  { h }
  writeln(it.name[1]);                  { i }

  q := @p;                              { typed C pointer to a record }
  writeln(q^.x);                        { 3 }
  writeln(q^.y);                        { 4 }
end.
