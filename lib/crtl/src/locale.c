/* SPDX-License-Identifier: Zlib */
/* C runtime: locale — fixed "C" locale (libc-free). lua reads only
   localeconv()->decimal_point. Filled at call time so the string-literal address
   is materialised at runtime (a global struct-with-pointer init would zero). */
#include <locale.h>

static struct lconv __crtl_lconv;

struct lconv *localeconv(void) {
  __crtl_lconv.decimal_point = ".";
  __crtl_lconv.thousands_sep = "";
  __crtl_lconv.grouping = "";
  return &__crtl_lconv;
}

char *setlocale(int category, const char *locale) {
  (void)category; (void)locale;
  return "C";
}
