/* Regression: a LOCAL array of function pointers with a brace initializer
   `int (*fp[2])(int) = {inc, dbl};` was rejected — the local declarator path
   didn't recognize the array-of-fn-ptr shape (bug-c-local-fnptr-array-initializer).
   Exit 42. */
static int inc(int x){ return x + 1; }
static int dbl(int x){ return x * 2; }
static int neg(int x){ return -x; }
int main(void){
  int (*fp[3])(int) = { inc, dbl, neg };
  int i, v = 3;
  for (i = 0; i < 3; i++) v = fp[i](v);   /* neg(dbl(inc(3))) = neg(8) = -8 */
  /* also index/call directly */
  if (v == -8 && fp[0](10) == 11 && fp[1](10) == 20 && fp[2](10) == -10)
    return 42;
  return 0;
}
