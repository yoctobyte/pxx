/* Constant-expression `/` and `%` (e.g. array sizes `sizeof(a)/sizeof(a[0])`).
   CEvalConstMul handled only `*`. Exit 42. */
int main(void) {
  int a[8 / 4];          /* size 2 */
  int b[17 % 5];         /* size 2 */
  int c[sizeof(long) / sizeof(int)];   /* size 2 (8/4) */
  a[1] = 20; b[1] = 13; c[1] = 9;
  return a[1] + b[1] + c[1];           /* 20 + 13 + 9 = 42 */
}
