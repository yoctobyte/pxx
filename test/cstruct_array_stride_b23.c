/* Array of structs uses sizeof(struct) stride; a[i] and p[i] must agree. Exit 42. */
struct V { int x; int y; };
int main(void) {
  struct V a[4];
  a[2].x = 18; a[2].y = 24;
  struct V *p = a;
  int viaArr = a[2].x + a[2].y;   /* 42 */
  int viaPtr = p[2].x + p[2].y;   /* 42 - must equal viaArr */
  return (viaArr == viaPtr) ? viaArr : 0;
}
