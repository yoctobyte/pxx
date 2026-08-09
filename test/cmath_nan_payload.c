#include <stdio.h>
#include <math.h>
#include <string.h>
static void P(const char *t, double v) {
  unsigned long long x; memcpy(&x, &v, 8);
  printf("%-10s %016llX\n", t, x);
}
int main(void) {
  P("empty", nan(""));
  P("1", nan("1"));
  P("12345", nan("12345"));
  P("0x10", nan("0x10"));
  P("abc", nan("abc"));
  P("077", nan("077"));
  P("big", nan("9007199254740993"));
  return 0;
}
