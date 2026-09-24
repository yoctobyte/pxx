/* THE REFUSAL THAT STAYS: a variadic returning a struct BY VALUE on windowed
 * xtensa. The hidden result pointer takes argument word 0 there and the va
 * save area does not model it, so building this would read every variadic
 * argument one word off -- wrong VALUES, not a diagnostic. It must refuse
 * until that is modelled. feature-a-variadic-c-functions-on-the-windowed-xtensa-abi */
#include <stdarg.h>

struct big { int a, b, c, d, e; };

static struct big pick(int n, ...) {
  struct big r = {0, 0, 0, 0, 0};
  va_list ap;
  va_start(ap, n);
  r.a = va_arg(ap, int);
  va_end(ap);
  return r;
}

int main(void) { return pick(1, 7).a - 7; }
