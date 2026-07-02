/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_STDDEF_H
#define PXX_CRTL_STDDEF_H 1

typedef unsigned long size_t;
typedef long ptrdiff_t;

#ifndef NULL
#define NULL 0
#endif

#define offsetof(type, member) ((size_t)&(((type *)0)->member))

#endif
