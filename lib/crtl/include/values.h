/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <values.h>, the SVR4 header of type sizes and limits, kept by
 * glibc for old code; <limits.h> and <float.h> are the standard ones. mksh's
 * sh.h includes it whenever it exists (HAVE_VALUES_H) and uses none of it.
 * The macros are glibc's set exactly (no more: BITS and the like are names
 * programs define for themselves), defined from those two headers.
 */
#ifndef _CRTL_VALUES_H
#define _CRTL_VALUES_H
#include <limits.h>
#include <float.h>

#define BITSPERBYTE CHAR_BIT
#define CHARBITS   (sizeof(char) * CHAR_BIT)
#define SHORTBITS  (sizeof(short) * CHAR_BIT)
#define INTBITS    (sizeof(int) * CHAR_BIT)
#define LONGBITS   (sizeof(long) * CHAR_BIT)
#define PTRBITS    (sizeof(char *) * CHAR_BIT)
#define DOUBLEBITS (sizeof(double) * CHAR_BIT)
#define FLOATBITS  (sizeof(float) * CHAR_BIT)

#define MINSHORT SHRT_MIN
#define MININT   INT_MIN
#define MINLONG  LONG_MIN
#define MAXSHORT SHRT_MAX
#define MAXINT   INT_MAX
#define MAXLONG  LONG_MAX

#define HIBITS  MINSHORT
#define HIBITL  MINLONG

#define MAXDOUBLE DBL_MAX
#define MAXFLOAT  FLT_MAX
#define MINDOUBLE DBL_MIN
#define MINFLOAT  FLT_MIN
#define DMINEXP   DBL_MIN_EXP
#define FMINEXP   FLT_MIN_EXP
#define DMAXEXP   DBL_MAX_EXP
#define FMAXEXP   FLT_MAX_EXP

#endif
