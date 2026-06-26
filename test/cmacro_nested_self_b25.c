/* A function-macro argument containing a nested call to the SAME macro (directly
   or via another macro) must expand — per C, args expand outside the macro's own
   replacement. lua's check_exp(c, gco2ccl(...)) where gco2ccl expands to another
   check_exp hits this. Exit 42. */
#define PICK(c, e) (e)
#define WRAP(o)    PICK(1, (o) + 20)
#define DBL(x)     ((x) * 2)
int main(void) {
  int a = PICK(0, WRAP(2));      /* WRAP->PICK in an arg: (2)+20 = 22 */
  int b = DBL(DBL(5));           /* legit nested same-macro arg: 20 */
  return a + b;                  /* 22 + 20 = 42 */
}
