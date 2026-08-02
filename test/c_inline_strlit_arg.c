/* bug-a-o3-inline-retention-substitutes-a-global-read-across-a-call
 *
 * A STRING LITERAL passed to a Pointer parameter needs the +8 skip over the
 * frozen string's length prefix. Every ordinary position (call argument,
 * assignment, binop, return) applies it; the -O3 inline splice's argument
 * TEMP-CAPTURE did not, so the callee received a pointer at the length prefix.
 *
 * It only bites at -O3, and only through a shim whose retained body contains a
 * call — that is what forces every argument to be temp-captured instead of
 * substituted directly. __pxx_open is exactly that shape (`Result :=
 * PalOpen(...)`), so `__pxx_open("/etc/localtime", 0, 0)` opened garbage,
 * returned -2, and localtime() silently reported UTC for every zone.
 *
 * The literal-vs-variable pair below IS the test: passing the same path through
 * a `const char *` always worked (the assignment applied the decay), which is
 * why this survived. Run at -O0, -O2 and -O3; the three must agree.
 */
#include <stdio.h>

extern int __pxx_open(const char *p, int flags, int mode);
extern int __pxx_close(int fd);

int main(void) {
  const char *p = "/etc/localtime";
  int a = __pxx_open("/etc/localtime", 0, 0);   /* literal   — the broken one */
  int b = __pxx_open(p, 0, 0);                  /* variable  — always worked  */
  printf("literal_ok=%d variable_ok=%d\n", a >= 0, b >= 0);
  if (a >= 0) __pxx_close(a);
  if (b >= 0) __pxx_close(b);
  return 0;
}
