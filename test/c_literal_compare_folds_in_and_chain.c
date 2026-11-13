/* libtommath's MP_HAS, verbatim: `(sizeof(""#BN_x_C"") == 1u)` is 1 when the
 * algorithm's BN_x_C macro is defined empty and 0 when it is not. mp_mul
 * guards each algorithm with `if (MP_HAS(X) && size test) err = s_mp_x(...)`,
 * and the configured-out algorithms are not compiled at all, so the dead arm
 * must not survive into the object: gcc drops it at -O0.
 *
 * pxx folded the comparison only later, at the IR's constant branch, so a
 * bare `if (MP_HAS(X))` was pruned, but `MP_HAS(X) && n > 3` was not, because
 * the && short-circuit asks whether its LEFT operand is a literal and saw a
 * binop. dropbear's mp_mul and mp_sqr kept four calls to undefined functions.
 *
 * The gone_* functions are declared and NEVER DEFINED: if any call survives,
 * this program does not link. The kept_* ones are live arms and are defined.
 * Expected output is gcc's.
 */
#include <stdio.h>

#define MP__STRINGIZE(x) ""#x""
#define MP_STRINGIZE(x)  MP__STRINGIZE(x)
#define MP_HAS(x)        (sizeof(MP_STRINGIZE(BN_##x##_C)) == 1u)
#define BN_YES_C

extern int gone_and(int);
extern int gone_or(int);
extern int gone_ne(int);
extern int gone_lt(int);
extern int gone_ternary(int);

static int kept_yes(int n) { return n * 2; }
static int kept_or(int n) { return n + 1000; }

static int f(int n)
{
  int r = 0;
  if (MP_HAS(NO) && (n > 3)) r = gone_and(n);
  else if (MP_HAS(YES) && n > 3) r = kept_yes(n);
  if ((sizeof("ab") != 3u || sizeof("") > 1) && n) r = gone_or(n);
  if ((sizeof("abc") != 4) && n) r = gone_ne(n);
  if ((sizeof("abc") < 2u) && n) r = gone_lt(n);
  if ((sizeof("") >= 1) || n) r += kept_or(n);
  r += (MP_HAS(NO) && n) ? gone_ternary(n) : 7;
  return r;
}

int main(void)
{
  printf("%d %d %d\n", f(1), f(5), f(0));
  printf("has %d %d\n", (int)MP_HAS(YES), (int)MP_HAS(NO));
  return 0;
}
