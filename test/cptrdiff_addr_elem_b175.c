/* Regression: ptrdiff of &-of-array-element expressions must divide by the
   element size. `&x[1] - &x[0]` == 1, not sizeof(int). The stride is derived
   from the indexed base (works for arrays and for pointer bases like u16*). */
int main(void){
  int x[4];
  long long a[3];
  short s[5];
  if (&x[1] - &x[0] != 1) return 1;
  if (&x[3] - &x[0] != 3) return 2;
  if (&a[2] - &a[0] != 2) return 3;   /* 8-byte elements */
  if (&s[4] - &s[1] != 3) return 4;   /* 2-byte elements */
  return 42;
}
