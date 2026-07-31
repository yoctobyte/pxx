/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_ERRNO_H
#define PXX_CRTL_ERRNO_H 1

extern int errno;

#define EPERM 1
#define ENOENT 2
#define ESRCH 3
#define EINTR 4
#define EIO 5
#define ENXIO 6
#define E2BIG 7
#define ENOEXEC 8
#define EBADF 9
#define ECHILD 10
#define EAGAIN 11
#define ENOMEM 12
#define EACCES 13
#define EFAULT 14
#define EBUSY 16
#define EEXIST 17
#define EXDEV 18
#define ENODEV 19
#define ENOTDIR 20
#define EISDIR 21
#define EINVAL 22
#define ENFILE 23
#define EMFILE 24
#define ENOTTY 25
#define EFBIG 27
#define ENOSPC 28
#define ESPIPE 29
#define EROFS 30
#define EMLINK 31
#define EPIPE 32
#define ERANGE 34
#define ETIMEDOUT 110

/* ---- the rest of the Linux/x86-64 set ----------------------------------
   Every value below was printed by a gcc-built program including glibc's
   <errno.h> on this target, not copied from documentation: these numbers are
   an ABI, a wrong one is silent, and a MISSING one is worse than wrong.

   Missing is worse because an undeclared identifier is "treated as 0" with
   only a warning, so `if (errno == ECONNREFUSED)` compiled to `errno == 0` --
   which is the SUCCESS value, i.e. the branch fired exactly when it should not
   have. 39 of the 71 names real code uses were in that state, including the
   entire socket family, which is why net-facing C could not diagnose a single
   connection error by name.

   Kept in numeric order with the block above; note the two deliberate
   aliases, which glibc also defines this way on Linux:
     EWOULDBLOCK == EAGAIN     (11)
     ENOTSUP     == EOPNOTSUPP (95)  */

#define ENOTBLK 15
#define ETXTBSY 26
#define EDOM 33
#define EDEADLK 35
#define ENAMETOOLONG 36
#define ENOLCK 37
#define ENOSYS 38
#define ENOTEMPTY 39
#define ELOOP 40
#define EWOULDBLOCK 11
#define ENOMSG 42
#define EIDRM 43
#define EOVERFLOW 75
#define EILSEQ 84
#define ENOTSOCK 88
#define EDESTADDRREQ 89
#define EMSGSIZE 90
#define EPROTOTYPE 91
#define ENOPROTOOPT 92
#define EPROTONOSUPPORT 93
#define EOPNOTSUPP 95
#define ENOTSUP 95
#define EAFNOSUPPORT 97
#define EADDRINUSE 98
#define EADDRNOTAVAIL 99
#define ENETDOWN 100
#define ENETUNREACH 101
#define ENETRESET 102
#define ECONNABORTED 103
#define ECONNRESET 104
#define ENOBUFS 105
#define EISCONN 106
#define ENOTCONN 107
#define ECONNREFUSED 111
#define EHOSTDOWN 112
#define EHOSTUNREACH 113
#define EALREADY 114
#define EINPROGRESS 115
#define ECANCELED 125

#endif
