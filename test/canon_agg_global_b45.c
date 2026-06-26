/* Inline anonymous struct/union as a TYPE (global var, param), not just a tagged
   reference (lua lstrlib `static const union {int dummy; char little;}
   nativeendian`). Values set at runtime (global = {..} initializer DATA is a
   separate gap). Exit 42. */
union { int dummy; char bytes[4]; } ne;
struct { int a; int b; } gs;
int firstbyte(union { int dummy; char bytes[4]; } *u) { return u->bytes[0]; }
int main(void) {
  ne.dummy = 1;                 /* little-endian: bytes[0] == 1 */
  gs.a = 0; gs.b = 41;
  return firstbyte(&ne) + gs.b; /* 1 + 41 = 42 */
}
