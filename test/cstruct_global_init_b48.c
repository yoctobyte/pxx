/* Non-array struct/union global brace-initializers materialised via PendingInit,
   each field name-resolved to its correct byte offset (mixed types too). Exit 42. */
struct { char x; int y; short z; } s = {5, 30, 7};   /* distinct offsets */
union  { int dummy; char b; } u = {1};
int main(void) {
  return s.x + s.y + s.z + (u.b == 1 ? 0 : 99);      /* 5 + 30 + 7 = 42 */
}
