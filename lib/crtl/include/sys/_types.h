/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS__TYPES_H
#define PXX_CRTL_SYS__TYPES_H 1

typedef long __off_t;
typedef unsigned long __size_t;
typedef long __ssize_t;
typedef long __time_t;
/* socklen_t's underlying type. It lives HERE, in the leaf header that pulls no
   implementation, so that <netdb.h> can spell `struct addrinfo' without first
   including <sys/socket.h> -- whose completion splices src/sys/socket.c and,
   through it, src/netinet/in.c, in the middle of netdb.h. See netdb.h. */
typedef unsigned int __socklen_t;

/* pid_t's underlying type, here for the same reason: <termios.h> deliberately
   includes NOTHING (its own note), and tcgetsid returns a pid_t. Reaching it
   through <sys/types.h> would give termios.h a first include and the splice
   that comes with one. */
typedef long __pid_t;

#endif
