{ C struct tag namespace: a bare `struct Inner` (no typedef) used by value
  through its tag, and a self-referential `struct Node` that points to itself
  via its own tag. Both require registering the struct tag as a resolvable
  record (forward-registered before the body so the self-reference resolves). }
program test_c_struct_tags;
uses cstructtags;
var
  o: Outer;
  n1, n2: Node;
begin
  o.in.a := 3;
  o.in.b := 4;
  o.c := 5;
  writeln(o.in.a + o.in.b + o.c);   { 12 — bare-tag struct by value }

  n2.val := 20; n2.next := nil;
  n1.val := 10; n1.next := @n2;
  writeln(n1.val);                  { 10 }
  writeln(n1.next^.val);            { 20 — self-ref pointer deref + field }
end.
