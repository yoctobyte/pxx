/* SPDX-License-Identifier: Zlib */
/* C runtime: locale — fixed "C" locale (libc-free). lua reads only
   localeconv()->decimal_point. Filled at call time so the string-literal address
   is materialised at runtime (a global struct-with-pointer init would zero). */
#include <locale.h>
#include <errno.h>
#include <string.h>

static struct lconv __crtl_lconv;

struct lconv *localeconv(void) {
  __crtl_lconv.decimal_point = ".";
  __crtl_lconv.thousands_sep = "";
  __crtl_lconv.grouping = "";
  /* the "C" locale's monetary part: empty strings, CHAR_MAX (127) numbers */
  __crtl_lconv.int_curr_symbol = "";
  __crtl_lconv.currency_symbol = "";
  __crtl_lconv.mon_decimal_point = "";
  __crtl_lconv.mon_thousands_sep = "";
  __crtl_lconv.mon_grouping = "";
  __crtl_lconv.positive_sign = "";
  __crtl_lconv.negative_sign = "";
  __crtl_lconv.int_frac_digits = 127;
  __crtl_lconv.frac_digits = 127;
  __crtl_lconv.p_cs_precedes = 127;
  __crtl_lconv.p_sep_by_space = 127;
  __crtl_lconv.n_cs_precedes = 127;
  __crtl_lconv.n_sep_by_space = 127;
  __crtl_lconv.p_sign_posn = 127;
  __crtl_lconv.n_sign_posn = 127;
  __crtl_lconv.int_p_cs_precedes = 127;
  __crtl_lconv.int_p_sep_by_space = 127;
  __crtl_lconv.int_n_cs_precedes = 127;
  __crtl_lconv.int_n_sep_by_space = 127;
  __crtl_lconv.int_p_sign_posn = 127;
  __crtl_lconv.int_n_sign_posn = 127;
  return &__crtl_lconv;
}

/* setlocale(3). Two locales exist: C (also spelled POSIX) and C.UTF-8 (also
   C.utf8, or any spelling of the codeset that normalises to "utf8", as glibc
   accepts). They differ only in LC_CTYPE: C.UTF-8 selects UTF-8 multibyte
   conversion and the Unicode character tables (stdlib.c, wchar.c, wctype.c),
   and every other category behaves as C, which is also true of glibc's.
   Any other name fails with NULL and changes nothing -- what glibc does for a
   locale that is not installed -- because crtl has no locale data for it.
   feature-crtl-c-utf8-locale

   Names are glibc's to the letter: the name is returned as it was given, ""
   resolves LC_ALL, then LC_<category>, then LANG, then "C"; and an LC_ALL
   query over mixed categories returns glibc's composite
   "LC_CTYPE=...;LC_NUMERIC=...;..." string, in its category order. On ESP
   there is no C.UTF-8 (its tables are not built there), so only C succeeds. */
#include <stdlib.h>

#define CRTL_NCAT 13              /* LC_CTYPE 0 .. LC_IDENTIFICATION 12, LC_ALL 6 */
#define CRTL_NAMELEN 32
static char crtl_cat_name[CRTL_NCAT][CRTL_NAMELEN];
static const char *const crtl_cat_env[CRTL_NCAT] = {
  "LC_CTYPE", "LC_NUMERIC", "LC_TIME", "LC_COLLATE", "LC_MONETARY", "LC_MESSAGES",
  "LC_ALL", "LC_PAPER", "LC_NAME", "LC_ADDRESS", "LC_TELEPHONE", "LC_MEASUREMENT",
  "LC_IDENTIFICATION"
};

/* 0 = not a locale crtl has, 1 = C, 2 = C.UTF-8 */
static int crtl_locale_kind(const char *name) {
  char cs[16];
  int n = 0;
  if (!strcmp(name, "C") || !strcmp(name, "POSIX")) return 1;
#ifndef __PXX_PLATFORM_ESP__
  if (name[0] == 'C' && name[1] == '.') {
    const char *p;
    for (p = name + 2; *p && n < 15; p++)
      if ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'z')) cs[n++] = *p;
      else if (*p >= 'A' && *p <= 'Z') cs[n++] = (char)(*p - 'A' + 'a');
    cs[n] = 0;
    if (!*p && !strcmp(cs, "utf8")) return 2;
  }
#endif
  return 0;
}

static const char *crtl_resolve(int cat, const char *locale) {
  const char *v;
  if (*locale) return locale;
  v = getenv("LC_ALL");
  if (v && *v) return v;
  v = getenv(crtl_cat_env[cat]);
  if (v && *v) return v;
  v = getenv("LANG");
  if (v && *v) return v;
  return "C";
}

static void crtl_init_names(void) {
  int i;
  if (crtl_cat_name[0][0]) return;
  for (i = 0; i < CRTL_NCAT; i++) strcpy(crtl_cat_name[i], "C");
}

static char *crtl_query_all(void) {
  static char composite[CRTL_NCAT * (20 + CRTL_NAMELEN)];
  int i, same = 1;
  for (i = 1; i < CRTL_NCAT; i++)
    if (i != LC_ALL && strcmp(crtl_cat_name[i], crtl_cat_name[0])) same = 0;
  if (same) return crtl_cat_name[0];
  composite[0] = 0;
  for (i = 0; i < CRTL_NCAT; i++) {
    if (i == LC_ALL) continue;
    if (composite[0]) strcat(composite, ";");
    strcat(composite, crtl_cat_env[i]);
    strcat(composite, "=");
    strcat(composite, crtl_cat_name[i]);
  }
  return composite;
}

char *setlocale(int category, const char *locale) {
  const char *want[CRTL_NCAT];
  int i;
  crtl_init_names();
  if (category < 0 || category >= CRTL_NCAT) { errno = EINVAL; return 0; }
  if (!locale) return category == LC_ALL ? crtl_query_all() : crtl_cat_name[category];
  /* decide every category before changing any: a failed LC_ALL changes nothing */
  for (i = 0; i < CRTL_NCAT; i++) {
    want[i] = 0;
    if (i == LC_ALL || (category != LC_ALL && i != category)) continue;
    want[i] = crtl_resolve(i, locale);
    if (!crtl_locale_kind(want[i]) || strlen(want[i]) >= CRTL_NAMELEN) {
      errno = ENOENT;
      return 0;
    }
  }
  for (i = 0; i < CRTL_NCAT; i++) {
    if (!want[i]) continue;
    /* glibc answers "C" for POSIX, and a C.UTF-8 spelling as it was given */
    strcpy(crtl_cat_name[i], crtl_locale_kind(want[i]) == 1 ? "C" : want[i]);
  }
  __crtl_ctype_utf8 = crtl_locale_kind(crtl_cat_name[LC_CTYPE]) == 2;
  return category == LC_ALL ? crtl_query_all() : crtl_cat_name[category];
}


/* The locale objects (see <locale.h>): one per locale crtl has, C and
   C.UTF-8, and __c is which (crtl_locale_kind). They are static and shared, so
   duplocale returns its argument and freelocale has nothing to free. Only
   LC_CTYPE differs between the two, so an object is its LC_CTYPE.
   feature-crtl-c-utf8-locale */
struct __pxx_locale { int __c; };
static struct __pxx_locale __crtl_c_locale = {1};
static struct __pxx_locale __crtl_utf8_locale = {2};

locale_t newlocale(int mask, const char *name, locale_t base) {
  int kind;
  if (!name) { errno = EINVAL; return 0; }
  kind = crtl_locale_kind(crtl_resolve(LC_CTYPE, name));
  if (!kind) { errno = ENOENT; return 0; }
  /* the categories not in mask come from base (glibc modifies base) */
  if (!(mask & LC_CTYPE_MASK))
    kind = (base && base != LC_GLOBAL_LOCALE) ? base->__c : 1;
  return kind == 2 ? &__crtl_utf8_locale : &__crtl_c_locale;
}

locale_t duplocale(locale_t loc) {
  if (loc == LC_GLOBAL_LOCALE) return __crtl_ctype_utf8 ? &__crtl_utf8_locale : &__crtl_c_locale;
  return loc;
}
void freelocale(locale_t loc) { (void)loc; }

/* Per thread, as in POSIX: uselocale(0) queries, LC_GLOBAL_LOCALE goes back
   to the setlocale one, an object installs it for this thread only. The
   thread's choice is read by every UTF-8 check (__crtl_utf8, stdlib.c). */
locale_t uselocale(locale_t loc) {
  int old = __crtl_thread_locale(-1);
  if (loc) __crtl_thread_locale(loc == LC_GLOBAL_LOCALE ? 0 : loc->__c);
  if (!old) return LC_GLOBAL_LOCALE;
  return old == 2 ? &__crtl_utf8_locale : &__crtl_c_locale;
}
