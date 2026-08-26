/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_STRING_H
#define PXX_CRTL_STRING_H 1

#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);

size_t strlen(const char *s);
/* POSIX: stops at maxlen, so a non-terminated fixed-width field is safe. */
size_t strnlen(const char *s, size_t maxlen);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, size_t n);
char *strcpy(char *dest, const char *src);
char *strncpy(char *dest, const char *src, size_t n);
char *strcat(char *dest, const char *src);
char *strncat(char *dest, const char *src, size_t n);
char *strchr(const char *s, int c);

/* The assumed-libc batch (feature-crtl-libc-gap-batch-2026-08). stpcpy returns
   the destination's NUL, not its start; memccpy stops AFTER the first c;
   strsep yields an EMPTY token between adjacent delimiters where strtok skips
   them, which is what ':'-field parsers depend on. */
char *stpcpy(char *dest, const char *src);
void *memccpy(void *dest, const void *src, int c, size_t n);
void *memrchr(const void *s, int c, size_t n);
char *strsep(char **stringp, const char *delim);
char *strcasestr(const char *haystack, const char *needle);
char *strrchr(const char *s, int c);
char *strstr(const char *haystack, const char *needle);
char *strpbrk(const char *s, const char *accept);
size_t strspn(const char *s, const char *accept);
size_t strcspn(const char *s, const char *reject);
char *strtok(char *s, const char *delim);
char *strtok_r(char *s, const char *delim, char **saveptr);
int strcoll(const char *a, const char *b);
size_t strxfrm(char *dest, const char *src, size_t n);
void *memchr(const void *s, int c, size_t n);
char *strerror(int errnum);
/* XSI strerror_r: fills buf, returns 0 or ERANGE. Deliberately the XSI form,
   not GNU's char*-returning one — they disagree on the return type. */
int strerror_r(int errnum, char *buf, size_t buflen);

/* glibc's <string.h> pulls in <strings.h> under __USE_MISC, so a program that
   includes only <string.h> still gets strcasecmp/strncasecmp/bzero/ffs. Real
   code leans on that: busybox reaches strncasecmp from libbb.h, which includes
   <string.h> and never <strings.h>, and it was the single largest cause of
   "call to undeclared function" across a busybox sweep.

   Gated the way glibc gates it, and for the same reason: <strings.h> defines
   index() and ffs(), and `index` in particular is an extremely common local
   variable name. A strict-ISO translation unit must not have those names
   appear just because it asked for <string.h>. */
#if defined(_GNU_SOURCE) || defined(_DEFAULT_SOURCE) || defined(_BSD_SOURCE)
#include <strings.h>
#endif

#endif
