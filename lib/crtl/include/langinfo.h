/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <langinfo.h> -- nl_langinfo for the one locale crtl has ("C").
 * The item numbers are crtl's own (nothing outside this runtime interprets
 * them); the answers are glibc's C-locale strings, measured. CODESET in
 * particular is "ANSI_X3.4-1968", glibc's name for ASCII, so a program that
 * checks for "UTF-8" (toybox's main) learns the truth and asks newlocale for a
 * UTF-8 locale, which fails here as it does on a glibc without one.
 */
#ifndef PXX_CRTL_LANGINFO_H
#define PXX_CRTL_LANGINFO_H 1

#include <locale.h>

typedef int nl_item;

enum {
  CODESET = 1, RADIXCHAR, THOUSEP, D_T_FMT, D_FMT, T_FMT, T_FMT_AMPM,
  AM_STR, PM_STR, ERA, ERA_D_FMT, ALT_DIGITS, ERA_D_T_FMT, ERA_T_FMT,
  YESEXPR, NOEXPR, CRNCYSTR,
  DAY_1 = 32, DAY_2, DAY_3, DAY_4, DAY_5, DAY_6, DAY_7,
  ABDAY_1 = 48, ABDAY_2, ABDAY_3, ABDAY_4, ABDAY_5, ABDAY_6, ABDAY_7,
  MON_1 = 64, MON_2, MON_3, MON_4, MON_5, MON_6, MON_7, MON_8, MON_9,
  MON_10, MON_11, MON_12,
  ABMON_1 = 80, ABMON_2, ABMON_3, ABMON_4, ABMON_5, ABMON_6, ABMON_7,
  ABMON_8, ABMON_9, ABMON_10, ABMON_11, ABMON_12
};
#define RADIXCHAR RADIXCHAR
#define THOUSEP THOUSEP

char *nl_langinfo(nl_item item);
char *nl_langinfo_l(nl_item item, locale_t loc);

#endif
