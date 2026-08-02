/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LIMITS_H
#define PXX_CRTL_LIMITS_H 1

#define CHAR_BIT 8
#define SCHAR_MIN (-128)
#define SCHAR_MAX 127
#define UCHAR_MAX 255U
#define CHAR_MIN SCHAR_MIN
#define CHAR_MAX SCHAR_MAX
#define SHRT_MIN (-32768)
#define SHRT_MAX 32767
#define USHRT_MAX 65535U
#define INT_MIN (-2147483647 - 1)
#define INT_MAX 2147483647
#define UINT_MAX 4294967295U
/* long is target-width: 64-bit on x86-64/aarch64, 32-bit on i386/arm32. These
   were hardcoded to the 64-bit values on EVERY target, so on i386 and arm32
   LONG_MAX was larger than a long can hold — a bound check against it never
   fired, and `x == LONG_MAX` was false for a value that really was the maximum.
   __SIZEOF_LONG__ is predefined per target by the C frontend. */
#if defined(__SIZEOF_LONG__) && __SIZEOF_LONG__ == 4
#define LONG_MIN (-2147483647L - 1L)
#define LONG_MAX 2147483647L
#define ULONG_MAX 4294967295UL
#else
#define LONG_MIN (-9223372036854775807L - 1L)
#define LONG_MAX 9223372036854775807L
#define ULONG_MAX 18446744073709551615UL
#endif
#define LLONG_MIN (-9223372036854775807LL - 1LL)
#define LLONG_MAX 9223372036854775807LL
#define ULLONG_MAX 18446744073709551615ULL

#define _POSIX2_RE_DUP_MAX 255

#endif
