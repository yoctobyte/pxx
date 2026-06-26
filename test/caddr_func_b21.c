/* `&function` is the function-pointer value (C `&f == f`). lua takes &func for
   handler/method tables. Exit 42. */
typedef int (*Fn)(int);
int dbl(int x) { return x * 2; }
int neg(int x) { return -x; }
int call(Fn f, int v) { return f(v); }
int main(void) {
  Fn p = &dbl;                          /* &func assigned */
  Fn tbl[2]; tbl[0] = &dbl; tbl[1] = &neg;
  int a = call(&dbl, 21);               /* &func as arg -> 42 */
  int ok = (p == &dbl) && (tbl[0] == dbl) && (tbl[1] == &neg);
  return a + (ok ? 0 : 100);
}
