/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LOCALE_H
#define PXX_CRTL_LOCALE_H 1
/* Minimal "C" locale — lua only reads lconv.decimal_point. */
struct lconv {
  char *decimal_point;
  char *thousands_sep;
  char *grouping;
};
#define LC_ALL      0
#define LC_NUMERIC  4
struct lconv *localeconv(void);
char *setlocale(int category, const char *locale);
#endif
