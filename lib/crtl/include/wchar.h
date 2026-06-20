#ifndef PXX_CRTL_WCHAR_H
#define PXX_CRTL_WCHAR_H 1

#include <stddef.h>

#ifndef WCHAR_MIN
#define WCHAR_MIN (-2147483647 - 1)
#endif
#ifndef WCHAR_MAX
#define WCHAR_MAX 2147483647
#endif

typedef int wchar_t;
typedef int wint_t;

#define WEOF (-1)

size_t wcslen(const wchar_t *s);
wint_t towlower(wint_t c);
wint_t towupper(wint_t c);

#endif
