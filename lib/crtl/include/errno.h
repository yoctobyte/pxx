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

/* THE OTHER 62, ADDED 2026-09-04, AND THE REASON IS NOT COMPLETENESS.
   An errno name crtl does not define is not a compile error here: pxx's C
   frontend accepts an undeclared identifier used as a value and substitutes 0
   with a warning (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning
   -not-an-error). For most constants that produces a wrong request. FOR AN
   ERRNO IT INVERTS A TEST -- `if (errno == ENODATA)' becomes
   `if (errno == 0)', which is TRUE exactly when nothing went wrong. Found
   2026-09-04 by test/c_crtl_xattr_and_inotify.c, whose row 1 printed ENODATA
   for a call that had SUCCEEDED.

   So the set is filled rather than grown on demand: a missing one is not a gap
   that announces itself, and the whole table costs sixty lines.

   GENERATED from the kernel's own include/uapi/asm-generic/errno{,-base}.h,
   which is the table every target this compiler builds for uses -- x86, arm,
   aarch64, riscv and xtensa all take asm-generic. (mips, alpha, sparc and
   parisc do not, and none is a pxx target; if one becomes one, this file needs
   an #if and not an edit.) The 71 rows that were already here were checked
   against that same table first and all 71 agreed.

   The three aliases at the end are the kernel's own: it defines them as other
   names rather than as numbers, and so does this. */

#define ECHRNG             44
#define EL2NSYNC           45
#define EL3HLT             46
#define EL3RST             47
#define ELNRNG             48
#define EUNATCH            49
#define ENOCSI             50
#define EL2HLT             51
#define EBADE              52
#define EBADR              53
#define EXFULL             54
#define ENOANO             55
#define EBADRQC            56
#define EBADSLT            57
#define EBFONT             59
#define ENOSTR             60
#define ENODATA            61
#define ETIME              62
#define ENOSR              63
#define ENONET             64
#define ENOPKG             65
#define EREMOTE            66
#define ENOLINK            67
#define EADV               68
#define ESRMNT             69
#define ECOMM              70
#define EPROTO             71
#define EMULTIHOP          72
#define EDOTDOT            73
#define EBADMSG            74
#define ENOTUNIQ           76
#define EBADFD             77
#define EREMCHG            78
#define ELIBACC            79
#define ELIBBAD            80
#define ELIBSCN            81
#define ELIBMAX            82
#define ELIBEXEC           83
#define ERESTART           85
#define ESTRPIPE           86
#define EUSERS             87
#define ESOCKTNOSUPPORT    94
#define EPFNOSUPPORT       96
#define ESHUTDOWN          108
#define ETOOMANYREFS       109
#define ESTALE             116
#define EUCLEAN            117
#define ENOTNAM            118
#define ENAVAIL            119
#define EISNAM             120
#define EREMOTEIO          121
#define EDQUOT             122
#define ENOMEDIUM          123
#define EMEDIUMTYPE        124
#define ENOKEY             126
#define EKEYEXPIRED        127
#define EKEYREVOKED        128
#define EKEYREJECTED       129
#define EOWNERDEAD         130
#define ENOTRECOVERABLE    131
#define ERFKILL            132
#define EHWPOISON          133

#define EDEADLOCK          EDEADLK
#define EFSBADCRC          EBADMSG
#define EFSCORRUPTED       EUCLEAN

#endif
