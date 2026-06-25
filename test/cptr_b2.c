/* Slice B increment 2 fixture: pointers and arrays — address-of, dereference
   (read + write), fixed arrays, array/pointer subscript, pointer arithmetic,
   pointer parameters, char* over a string literal. Exit code asserted vs gcc. */
int slen(char *s) { int n = 0; while (s[n]) n++; return n; }
void swap(int *a, int *b) { int t = *a; *a = *b; *b = t; }
int sumv(int *a, int n) { int s = 0, i; for (i = 0; i < n; i++) s += a[i]; return s; }

int main(void) {
  int x = 3, y = 8;
  swap(&x, &y);                 /* x=8 y=3 */
  int r = x * 10 + y;           /* 83 */

  int a[6];
  int i;
  for (i = 0; i < 6; i++) a[i] = i + 1;  /* 1..6 */
  int *p = a;
  r += *(p + 2);                /* +3 -> 86 */
  p[5] = 100;                   /* a[5]=100 */
  r += a[5] - 100;              /* +0 */
  r += sumv(a, 5);              /* 1+2+3+4+5=15 -> 101 */

  int n = 5;
  int *q = &n;
  *q = *q + 4;                  /* n=9 */
  r += n;                       /* 110 */

  r += slen("hello world!");    /* +12 -> 122 */
  return r;                     /* 122 */
}
