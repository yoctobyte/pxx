/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_STDDEF_H
#define PXX_CRTL_STDDEF_H 1

typedef unsigned long size_t;
typedef long ptrdiff_t;

#ifndef NULL
#define NULL 0
#endif

#define offsetof(type, member) ((size_t)&(((type *)0)->member))

/* C99 7.17: <stddef.h> defines wchar_t, and it is the header most code reaches
   it through — <wchar.h> is for the wide-string FUNCTIONS. busybox's libbb.h
   pulls in <stddef.h> and spells `wchar_t` in libbb/unicode.c and
   libbb/lineedit.c without ever including <wchar.h>; with the typedef only in
   <wchar.h> those read as a stray token at top level. Guarded because <wchar.h>
   states the same typedef and C99 has no repeated-typedef allowance. */
#ifndef __PXX_WCHAR_T_DEFINED
#define __PXX_WCHAR_T_DEFINED 1
typedef int wchar_t;
#endif

#endif
