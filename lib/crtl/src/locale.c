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

#include <errno.h>
#include <string.h>

/* The one locale object (see <locale.h>). Its contents are never read; its
   address is the identity. */
struct __pxx_locale { int __c; };
static struct __pxx_locale __crtl_c_locale;

locale_t newlocale(int mask, const char *name, locale_t base) {
  (void)mask; (void)base;
  if (!name) { errno = EINVAL; return 0; }
  if (!*name || !strcmp(name, "C") || !strcmp(name, "POSIX"))
    return &__crtl_c_locale;
  errno = ENOENT;
  return 0;
}

locale_t duplocale(locale_t loc) { (void)loc; return &__crtl_c_locale; }
void freelocale(locale_t loc) { (void)loc; }

/* uselocale(0) queries; anything else installs -- and there is only one
   locale to install, so the answer is always the global one. */
locale_t uselocale(locale_t loc) { (void)loc; return LC_GLOBAL_LOCALE; }
