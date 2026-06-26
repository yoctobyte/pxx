/* Pointer-pointer subtraction `p - q` = element count = (addr diff)/sizeof(elem)
   (lua ldo `cast(unsigned short, firstres - ci->func.p)`). Was a silent
   miscompile (raw address diff / float division). Exit 42. */
struct S { int x, y; };
int main(void) {
  int a[8];
  int *p = &a[6], *q = a;
  int d1 = (int)(p - q);            /* 6 */
  struct S s[8];
  struct S *r = &s[4], *t = s;
  int d2 = (int)(r - t);            /* 4 */
  char b[20];
  char *cp = &b[5], *cq = b;
  int d3 = (int)(cp - cq);          /* 5 */
  int neg = (int)(q - p);           /* -6 */
  return d1 + d2 + d3 + neg + 33;   /* 6 + 4 + 5 - 6 + 33 = 42 */
}
