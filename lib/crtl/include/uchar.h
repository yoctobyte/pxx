/* SPDX-License-Identifier: Zlib */
/*
 * <uchar.h> (C11 7.28): char16_t, char32_t and their conversions. Written
 * from the standard. Without it a crtl program fell through to the host's
 * <uchar.h>, which drags glibc's bits/ headers in (systemd: 594 units, and
 * its bits/floatn.h then needs glibc's __GNUC_PREREQ).
 *
 * The conversions follow crtl's mbrtowc/wcrtomb, which are the C locale:
 * ASCII, everything above 0x7F EILSEQ, as glibc's C locale. c16rtomb keeps a
 * high surrogate in the state and combines it with the low one that follows,
 * as glibc does. feature-crtl-uchar-h
 */
#ifndef PXX_CRTL_UCHAR_H
#define PXX_CRTL_UCHAR_H 1

#include <stddef.h>
#include <stdint.h>
#include <wchar.h>

typedef uint_least16_t char16_t;
typedef uint_least32_t char32_t;
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
typedef unsigned char char8_t;
#endif

size_t mbrtoc16(char16_t *pc16, const char *s, size_t n, mbstate_t *ps);
size_t c16rtomb(char *s, char16_t c16, mbstate_t *ps);
size_t mbrtoc32(char32_t *pc32, const char *s, size_t n, mbstate_t *ps);
size_t c32rtomb(char *s, char32_t c32, mbstate_t *ps);

#endif
