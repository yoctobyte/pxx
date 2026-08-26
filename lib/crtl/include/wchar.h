/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_WCHAR_H
#define PXX_CRTL_WCHAR_H 1

#include <stddef.h>

#ifndef WCHAR_MIN
#define WCHAR_MIN (-2147483647 - 1)
#endif
#ifndef WCHAR_MAX
#define WCHAR_MAX 2147483647
#endif

#ifndef __PXX_WCHAR_T_DEFINED
#define __PXX_WCHAR_T_DEFINED 1
typedef int wchar_t;
#endif
typedef int wint_t;

/* C99 7.24.1: the conversion-state object. Its contents are unspecified and no
   portable code inspects them — what code needs is the TYPE, so it can name a
   parameter. busybox implements its own wcrtomb/mbstowcs and declares them as
   `(char *s, wchar_t wc, mbstate_t *ps)`; without the typedef the parameter
   list mis-parsed and the function body reached IR lowering as a bare integer
   literal ("could not lower AST node (kind 1)"). Laid out like glibc's so a
   sizeof is not wildly wrong. */
typedef struct {
  int __count;
  union { unsigned int __wch; char __wchb[4]; } __value;
} mbstate_t;

#define WEOF (-1)

size_t wcslen(const wchar_t *s);
wint_t towlower(wint_t c);
wint_t towupper(wint_t c);

#endif
