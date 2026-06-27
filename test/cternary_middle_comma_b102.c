/* The middle arm of C `?:` is a full expression, so a top-level comma belongs
   to that arm: `c ? (side = v), result : other`. sqlite's getVarint32 macro
   uses this shape inside a cast. Exit 42. */
int main(void) {
  int side = 0;
  int a = 1 ? (side = 41), 1 : (side = 99);
  int b = 0 ? (side = 99), 5 : 0;
  return side + a + b;
}
