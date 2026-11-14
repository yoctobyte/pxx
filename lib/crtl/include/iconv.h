/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <iconv.h> -- character set conversion between the Unicode
 * encodings and the two single-byte sets every system has: UTF-8, UTF-16LE/BE,
 * UTF-32LE/BE (WCHAR_T is UTF-32 in host order), ASCII and ISO-8859-1. Names
 * match case-insensitively with '-' and '_' ignored, so "utf8", "UTF-8" and
 * "Latin1" all resolve. iconv_open for any other name fails with EINVAL, the
 * answer glibc gives for a converter that is not installed. A character the
 * target cannot represent is EILSEQ, as in glibc without //TRANSLIT.
 */
#ifndef PXX_CRTL_ICONV_H
#define PXX_CRTL_ICONV_H 1

#include <stddef.h>

typedef void *iconv_t;

iconv_t iconv_open(const char *tocode, const char *fromcode);
size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft,
             char **outbuf, size_t *outbytesleft);
int iconv_close(iconv_t cd);

#endif
