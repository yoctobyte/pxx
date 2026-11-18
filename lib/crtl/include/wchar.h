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

/* The string and memory family (C99 7.24.4): plain loops over 32-bit units,
   no locale involved. st's selection code (wcschr over worddelimiters) needed
   the first of them. */
size_t   wcsnlen(const wchar_t *s, size_t maxlen);
wchar_t *wcschr(const wchar_t *s, wchar_t c);
wchar_t *wcsrchr(const wchar_t *s, wchar_t c);
int      wcscmp(const wchar_t *a, const wchar_t *b);
int      wcsncmp(const wchar_t *a, const wchar_t *b, size_t n);
wchar_t *wcscpy(wchar_t *d, const wchar_t *s);
wchar_t *wcsncpy(wchar_t *d, const wchar_t *s, size_t n);
wchar_t *wcscat(wchar_t *d, const wchar_t *s);
wchar_t *wcsncat(wchar_t *d, const wchar_t *s, size_t n);
size_t   wcsspn(const wchar_t *s, const wchar_t *accept);
size_t   wcscspn(const wchar_t *s, const wchar_t *reject);
wchar_t *wcspbrk(const wchar_t *s, const wchar_t *accept);
wchar_t *wcsstr(const wchar_t *hay, const wchar_t *needle);
wchar_t *wcsdup(const wchar_t *s);
wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n);
int      wmemcmp(const wchar_t *a, const wchar_t *b, size_t n);
wchar_t *wmemcpy(wchar_t *d, const wchar_t *s, size_t n);
wchar_t *wmemmove(wchar_t *d, const wchar_t *s, size_t n);
wchar_t *wmemset(wchar_t *d, wchar_t c, size_t n);

/* Multibyte conversion and display width in the C locale, which is ASCII:
   bytes 0..127 are their own wide characters and everything above is EILSEQ
   (or -1 for wcwidth). Measured against glibc's C locale: mbrtowc(0xE9) and
   wcrtomb(0xE9) are -1/EILSEQ, wcwidth is 1 for printable ASCII, 0 for L'\0'
   and -1 for controls and for every non-ASCII value (U+00E9, U+4E00). */
size_t mbrtowc(wchar_t *pwc, const char *s, size_t n, mbstate_t *ps);
size_t wcrtomb(char *s, wchar_t wc, mbstate_t *ps);
size_t mbrlen(const char *s, size_t n, mbstate_t *ps);
int mbsinit(const mbstate_t *ps);
wint_t btowc(int c);
int wctob(wint_t c);
int wcwidth(wchar_t wc);
int wcswidth(const wchar_t *s, size_t n);
wint_t towlower(wint_t c);
wint_t towupper(wint_t c);

#endif
