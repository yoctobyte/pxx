/* Regression: a tagged struct nested >=4 deep must not accumulate duplicate
   field windows across the C driver's multiple parse passes (pass1 signatures,
   pass2 bodies, crtl-prototype rerun). Before the ParseCStructInto redefinition
   guard, each re-parse re-appended the struct's fields, growing UClsFCount and
   overlapping the per-record field windows; at depth >=4 the overlap produced a
   record whose window pointed back into itself, and a whole-record copy sent
   RecordHasManagedFields / the copy path into an unbounded walk — the compiler
   HUNG on valid C (gcc-torture pr44164 / pr23324). This must compile in bounded
   time AND copy correctly. */
struct X { struct Y { struct YY { struct Z { int i; int j; } c; } bb; } b; } a, g;

int main(void) {
  g.b.bb.c.i = 42; g.b.bb.c.j = 7;
  a.b = g.b;              /* deep field-target whole-record copy */
  struct X t = a;         /* whole-struct copy of a >=4-deep type */
  if (t.b.bb.c.i != 42) return 1;
  if (t.b.bb.c.j != 7)  return 2;
  return 42;
}
