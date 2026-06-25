/* sizeof inside a constant expression (array dimension), e.g. lua's
   `char buff[3 * sizeof(size_t)]`. Exit 42. */
typedef unsigned long size_t;
int main(void) {
  char a[sizeof(int)];            /* 4 */
  char b[2 * sizeof(int) + 1];    /* 9 */
  char c[3 * sizeof(size_t)];     /* 24 */
  a[0] = b[0] = c[0] = 0;
  return (int)(sizeof(a) + sizeof(b) + sizeof(c) + 5);   /* 4+9+24+5 = 42 */
}
