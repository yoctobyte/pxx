/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LOCALE_H
#define PXX_CRTL_LOCALE_H 1
/* Minimal "C" locale — lua only reads lconv.decimal_point.
 *
 * THE CATEGORY NUMBERS ARE GLIBC'S, and they did not used to be: LC_ALL was 0
 * and LC_NUMERIC was 4, which are glibc's LC_CTYPE and LC_MONETARY. crtl's own
 * setlocale ignores the category, so nothing here could tell -- but a pxx
 * object is LINKED BY GCC in the busybox build, and a category constant
 * compiled from this header then reaches the real setlocale. `setlocale(LC_ALL,
 * value)' in ash.c would have set LC_CTYPE alone, and `setlocale(LC_NUMERIC,
 * "C")' in libbb/duration.c would have set LC_MONETARY, with no diagnostic
 * anywhere. A constant that is only ever passed to our own ignoring stub looks
 * free to choose; it is not, the moment the object leaves this runtime.
 *
 * The full set, not the two that were here: LC_COLLATE, LC_CTYPE, LC_MONETARY
 * and LC_TIME were missing, so lua's loslib.c and lstrlib.c compiled through
 * four `undeclared identifier used as value (treated as 0)' warnings on every
 * target and passed -- 0 is LC_CTYPE, and lua only ever hands the category to
 * a setlocale that ignores it. That is luck with a warning printed over it, and
 * it is the census case named in
 * bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error. */
struct lconv {
  char *decimal_point;
  char *thousands_sep;
  char *grouping;
};
#define LC_CTYPE          0
#define LC_NUMERIC        1
#define LC_TIME           2
#define LC_COLLATE        3
#define LC_MONETARY       4
#define LC_MESSAGES       5
#define LC_ALL            6
#define LC_PAPER          7
#define LC_NAME           8
#define LC_ADDRESS        9
#define LC_TELEPHONE     10
#define LC_MEASUREMENT   11
#define LC_IDENTIFICATION 12
struct lconv *localeconv(void);
char *setlocale(int category, const char *locale);
#endif
