/* SPDX-License-Identifier: Zlib */
/* C runtime: assert — the failure sink behind the assert() macro. */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

void __pxx_assert_fail(const char *expr, const char *file, int line) {
  fprintf(stderr, "assertion failed: %s (%s:%d)\n", expr, file, line);
  abort();
}
