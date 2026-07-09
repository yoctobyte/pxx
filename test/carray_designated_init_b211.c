/* Regression: C99/GNU designated + range initializers on a LOCAL scalar array.
   The block-scope array brace-init path parsed positionally only; `[k] =`,
   unsized designator sizing, mixed designated+positional, and `[lo ... hi] =`
   ranges now work. gcc-verified. feature-c-designated-init-compound-literals. */
int main(void) {
  int a[5] = { [2] = 7, [4] = 9 };
  int b[]  = { [3] = 30, [1] = 10, 11 };   /* unsized -> len 4; 11 lands at [2] */
  int c[8] = { [2 ... 5] = 7 };
  char d[] = { [1] = 'X', [0] = 'Y' };
  int i, cs = 0, ok = 1;

  if (!(a[0]==0 && a[1]==0 && a[2]==7 && a[3]==0 && a[4]==9)) ok = 0;
  if (!(b[0]==0 && b[1]==10 && b[2]==11 && b[3]==30)) ok = 0;
  for (i = 0; i < 8; i++) cs += c[i];
  if (cs != 28) ok = 0;                    /* [2..5]=7 -> 4*7 */
  if (!(d[0]=='Y' && d[1]=='X')) ok = 0;

  return ok ? 42 : 1;
}
