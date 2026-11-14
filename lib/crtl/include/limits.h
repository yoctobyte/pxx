/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LIMITS_H
#define PXX_CRTL_LIMITS_H 1

#define CHAR_BIT 8
#define SCHAR_MIN (-128)
#define SCHAR_MAX 127
/* UCHAR_MAX and USHRT_MAX are INT constants, as in glibc and gcc's own
   limits.h: an unsigned char or short promotes to int, so its maximum is an
   int. Spelled 255U, `-1 < UCHAR_MAX` was false (gcc: true) on every target. */
#define UCHAR_MAX 255
/* plain char follows the target: unsigned on aarch64, arm32 and riscv
   (the frontend predefines __CHAR_UNSIGNED__ there, as gcc does) */
#ifdef __CHAR_UNSIGNED__
#define CHAR_MIN 0
#define CHAR_MAX UCHAR_MAX
#else
#define CHAR_MIN SCHAR_MIN
#define CHAR_MAX SCHAR_MAX
#endif
#define SHRT_MIN (-32768)
#define SHRT_MAX 32767
#define USHRT_MAX 65535
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

/* POSIX's guaranteed MINIMUMS (<limits.h>, "Minimum Values"): fixed by the
   standard, not by the system, which is why they are constants. getconf lists
   them. Values generated from the numbers, one per name. */
#ifndef _POSIX_AIO_LISTIO_MAX
#define _POSIX_AIO_LISTIO_MAX                  2
#endif
#ifndef _POSIX_AIO_MAX
#define _POSIX_AIO_MAX                         1
#endif
#ifndef _POSIX_ARG_MAX
#define _POSIX_ARG_MAX                         4096
#endif
#ifndef _POSIX_CHILD_MAX
#define _POSIX_CHILD_MAX                       25
#endif
#ifndef _POSIX_DELAYTIMER_MAX
#define _POSIX_DELAYTIMER_MAX                  32
#endif
#ifndef _POSIX_HOST_NAME_MAX
#define _POSIX_HOST_NAME_MAX                   255
#endif
#ifndef _POSIX_LINK_MAX
#define _POSIX_LINK_MAX                        8
#endif
#ifndef _POSIX_LOGIN_NAME_MAX
#define _POSIX_LOGIN_NAME_MAX                  9
#endif
#ifndef _POSIX_MAX_CANON
#define _POSIX_MAX_CANON                       255
#endif
#ifndef _POSIX_MAX_INPUT
#define _POSIX_MAX_INPUT                       255
#endif
#ifndef _POSIX_NAME_MAX
#define _POSIX_NAME_MAX                        14
#endif
#ifndef _POSIX_NGROUPS_MAX
#define _POSIX_NGROUPS_MAX                     8
#endif
#ifndef _POSIX_OPEN_MAX
#define _POSIX_OPEN_MAX                        20
#endif
#ifndef _POSIX_PATH_MAX
#define _POSIX_PATH_MAX                        256
#endif
#ifndef _POSIX_PIPE_BUF
#define _POSIX_PIPE_BUF                        512
#endif
#ifndef _POSIX_RE_DUP_MAX
#define _POSIX_RE_DUP_MAX                      255
#endif
#ifndef _POSIX_RTSIG_MAX
#define _POSIX_RTSIG_MAX                       8
#endif
#ifndef _POSIX_SEM_NSEMS_MAX
#define _POSIX_SEM_NSEMS_MAX                   256
#endif
#ifndef _POSIX_SEM_VALUE_MAX
#define _POSIX_SEM_VALUE_MAX                   32767
#endif
#ifndef _POSIX_SIGQUEUE_MAX
#define _POSIX_SIGQUEUE_MAX                    32
#endif
#ifndef _POSIX_SSIZE_MAX
#define _POSIX_SSIZE_MAX                       32767
#endif
#ifndef _POSIX_STREAM_MAX
#define _POSIX_STREAM_MAX                      8
#endif
#ifndef _POSIX_SYMLINK_MAX
#define _POSIX_SYMLINK_MAX                     255
#endif
#ifndef _POSIX_SYMLOOP_MAX
#define _POSIX_SYMLOOP_MAX                     8
#endif
#ifndef _POSIX_THREAD_DESTRUCTOR_ITERATIONS
#define _POSIX_THREAD_DESTRUCTOR_ITERATIONS    4
#endif
#ifndef _POSIX_THREAD_KEYS_MAX
#define _POSIX_THREAD_KEYS_MAX                 128
#endif
#ifndef _POSIX_THREAD_THREADS_MAX
#define _POSIX_THREAD_THREADS_MAX              64
#endif
#ifndef _POSIX_TIMER_MAX
#define _POSIX_TIMER_MAX                       32
#endif
#ifndef _POSIX_TTY_NAME_MAX
#define _POSIX_TTY_NAME_MAX                    9
#endif
#ifndef _POSIX_TZNAME_MAX
#define _POSIX_TZNAME_MAX                      6
#endif
#ifndef _POSIX2_BC_BASE_MAX
#define _POSIX2_BC_BASE_MAX                    99
#endif
#ifndef _POSIX2_BC_DIM_MAX
#define _POSIX2_BC_DIM_MAX                     2048
#endif
#ifndef _POSIX2_BC_SCALE_MAX
#define _POSIX2_BC_SCALE_MAX                   99
#endif
#ifndef _POSIX2_BC_STRING_MAX
#define _POSIX2_BC_STRING_MAX                  1000
#endif
#ifndef _POSIX2_CHARCLASS_NAME_MAX
#define _POSIX2_CHARCLASS_NAME_MAX             14
#endif
#ifndef _POSIX2_COLL_WEIGHTS_MAX
#define _POSIX2_COLL_WEIGHTS_MAX               2
#endif
#ifndef _POSIX2_EXPR_NEST_MAX
#define _POSIX2_EXPR_NEST_MAX                  32
#endif
#ifndef _POSIX2_LINE_MAX
#define _POSIX2_LINE_MAX                       2048
#endif

#endif
