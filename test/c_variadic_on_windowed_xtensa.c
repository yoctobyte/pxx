/* A C VARIADIC DEFINITION on windowed xtensa -- the ABI ESP-IDF runs on the
 * esp32s3 -- as an --emit-obj row. Until 2026-09-24 the prologue refused it
 * ("only the call0 ABI is implemented"), and every c-testsuite program reaches
 * crtl's printf, so C on the s3 could not build at all.
 * feature-a-variadic-c-functions-on-the-windowed-xtensa-abi
 *
 * The VALUES are proven by booting, not here: tools/run_c_conformance_esp.sh
 * --chip esp32s3 runs the suite under QEMU. This row pins that it builds, and
 * that app_main at .text+0 is the windowed entry stub (entry a1,64). */
#include <stdarg.h>
#include <stdio.h>

static int sum(int n, ...) {
  va_list ap;
  int s = 0, i;
  va_start(ap, n);
  for (i = 0; i < n; i++) s = s * 10 + va_arg(ap, int);
  va_end(ap);
  return s;
}

int main(void) {
  printf("sum9=%d\n", sum(9, 1, 2, 3, 4, 5, 6, 7, 8, 9));
  return 0;
}
