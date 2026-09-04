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
/* LONG_BIT and WORD_BIT -- XSI, and DERIVED rather than written down, for
   exactly the reason the LONG_MAX split above exists. busybox's TLS AES-GCM
   code uses it as a SHIFT DISTANCE -- networking/tls_aesgcm.c:77 and :92 build
   the GHASH carry with `(unsigned long)0xE1 << (LONG_BIT-8)` and
   `tt << (LONG_BIT-1)`. With no definition here LONG_BIT became 0, so both
   shift counts went NEGATIVE. Nothing refuses: the authentication tag comes
   out wrong, on a code path that only a real TLS handshake reaches, which is
   why 621 green busybox cases never touched it.

   A literal 64 would have been just as wrong on i386 and arm32 as the old
   hardcoded LONG_MAX was, and would have read as correct on the host that does
   the measuring. */
#define LONG_BIT (__SIZEOF_LONG__ * CHAR_BIT)
#define WORD_BIT (__SIZEOF_INT__ * CHAR_BIT)

#define LLONG_MIN (-9223372036854775807LL - 1LL)
#define LLONG_MAX 9223372036854775807LL
#define ULLONG_MAX 18446744073709551615ULL

/* SSIZE_MAX -- the largest value an ssize_t holds, which is LONG_MAX because
   ssize_t is `long' here as it is in glibc. Written in terms of LONG_MAX rather
   than spelled out, so the 32-bit/64-bit split above is stated once.

   Not decoration: it is a BOUND, and a missing one does not fail to compile --
   pxx turns an undeclared identifier used as a value into 0 with a warning
   (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error).
   busybox's miscutils/bc.c compiled with SSIZE_MAX = 0, which makes every
   `len > SSIZE_MAX' check fire on the first byte. */
#define SSIZE_MAX LONG_MAX

#define _POSIX2_RE_DUP_MAX 255

/* POSIX/Linux path limits. Values are the kernel's, read off the host
   (linux/limits.h): NAME_MAX excludes the terminating NUL, PATH_MAX includes
   it. Both are constants on Linux rather than pathconf() answers, which is why
   a header can carry them at all. busybox's ash sizes a filename buffer with
   NAME_MAX, and an undeclared NAME_MAX was being treated as 0 -- a zero-length
   buffer rather than a compile error. */
#define NAME_MAX 255
#define PATH_MAX 4096

#endif
