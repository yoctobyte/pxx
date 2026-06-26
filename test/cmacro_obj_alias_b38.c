/* An object-like macro whose body is a function-macro NAME, then invoked with
   args: `#define A2 ADD` ... `A2(x, y)` must expand ADD with those args (lua's
   `#define setsvalue2n setsvalue`). Exit 42. */
#define ADD(a, b) ((a) + (b))
#define A2        ADD
#define INC(x)    ((x) + 1)
#define ALIAS     INC
int main(void) {
  int s = A2(18, 5);        /* ADD(18,5) = 23 */
  int t = ALIAS(18);        /* INC(18) = 19 */
  return s + t;             /* 23 + 19 = 42 */
}
