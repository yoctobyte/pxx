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
/* glibc's member order, so a --system-libs build and a crtl build agree on
   every offset (TinyX's fontxlfd.c reads positive_sign). */
struct lconv {
  char *decimal_point;
  char *thousands_sep;
  char *grouping;
  char *int_curr_symbol;
  char *currency_symbol;
  char *mon_decimal_point;
  char *mon_thousands_sep;
  char *mon_grouping;
  char *positive_sign;
  char *negative_sign;
  char int_frac_digits;
  char frac_digits;
  char p_cs_precedes;
  char p_sep_by_space;
  char n_cs_precedes;
  char n_sep_by_space;
  char p_sign_posn;
  char n_sign_posn;
  char int_p_cs_precedes;
  char int_p_sep_by_space;
  char int_n_cs_precedes;
  char int_n_sep_by_space;
  char int_p_sign_posn;
  char int_n_sign_posn;
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

/* POSIX 2008 locale objects. crtl has one locale, "C" (alias "POSIX", and ""
   which means "from the environment" and resolves to it), so newlocale hands
   back that one object for those names and fails with ENOENT for every other
   -- including "C.UTF-8", which glibc provides and crtl does not. That is what
   glibc does for a locale that is not installed, and the callers that try one
   name and then another (toybox's main) take the same path they take there. */
typedef struct __pxx_locale *locale_t;
#define LC_GLOBAL_LOCALE ((locale_t)-1L)
#define LC_CTYPE_MASK          (1 << LC_CTYPE)
#define LC_NUMERIC_MASK        (1 << LC_NUMERIC)
#define LC_TIME_MASK           (1 << LC_TIME)
#define LC_COLLATE_MASK        (1 << LC_COLLATE)
#define LC_MONETARY_MASK       (1 << LC_MONETARY)
#define LC_MESSAGES_MASK       (1 << LC_MESSAGES)
#define LC_PAPER_MASK          (1 << LC_PAPER)
#define LC_NAME_MASK           (1 << LC_NAME)
#define LC_ADDRESS_MASK        (1 << LC_ADDRESS)
#define LC_TELEPHONE_MASK      (1 << LC_TELEPHONE)
#define LC_MEASUREMENT_MASK    (1 << LC_MEASUREMENT)
#define LC_IDENTIFICATION_MASK (1 << LC_IDENTIFICATION)
#define LC_ALL_MASK (LC_CTYPE_MASK | LC_NUMERIC_MASK | LC_TIME_MASK | \
                     LC_COLLATE_MASK | LC_MONETARY_MASK | LC_MESSAGES_MASK | \
                     LC_PAPER_MASK | LC_NAME_MASK | LC_ADDRESS_MASK | \
                     LC_TELEPHONE_MASK | LC_MEASUREMENT_MASK | \
                     LC_IDENTIFICATION_MASK)
locale_t newlocale(int mask, const char *name, locale_t base);
locale_t duplocale(locale_t loc);
void freelocale(locale_t loc);
locale_t uselocale(locale_t loc);
#endif
