/* SPDX-License-Identifier: Zlib */
/*
 * <printf.h>, the part of the GNU extension that code outside glibc uses:
 * the argument-type codes and parse_printf_format(), written from the glibc
 * manual ("Parsing a Template String"); the numeric values are glibc's ABI.
 * systemd's VA_FORMAT_ADVANCE (stdio-util.h) walks a va_list with it. Without
 * this header a crtl program fell through to the host's, which drags glibc's
 * bits/floatn.h in (systemd: 109 units). register_printf_function and
 * friends are not provided. feature-crtl-printf-h-parse-printf-format
 */
#ifndef PXX_CRTL_PRINTF_H
#define PXX_CRTL_PRINTF_H 1

#include <stddef.h>
#include <stdio.h>

enum {
  PA_INT,          /* int */
  PA_CHAR,         /* int, cast to char */
  PA_WCHAR,        /* wide char */
  PA_STRING,       /* const char *, NUL-terminated */
  PA_WSTRING,      /* const wchar_t *, NUL-terminated */
  PA_POINTER,      /* void * */
  PA_FLOAT,        /* float */
  PA_DOUBLE,       /* double */
  PA_LAST
};

#define PA_FLAG_MASK        0xff00
#define PA_FLAG_LONG_LONG   (1 << 8)
#define PA_FLAG_LONG_DOUBLE PA_FLAG_LONG_LONG
#define PA_FLAG_LONG        (1 << 9)
#define PA_FLAG_SHORT       (1 << 10)
#define PA_FLAG_PTR         (1 << 11)

/* Store in argtypes[0..n-1] the type of each argument the template needs
   (a '*' width or precision is a PA_INT of its own) and return how many it
   needs in all, which may be more than n. */
size_t parse_printf_format(const char *fmt, size_t n, int *argtypes);

#endif
