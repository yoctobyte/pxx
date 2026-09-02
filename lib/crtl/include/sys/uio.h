/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/uio.h> -- scatter/gather I/O.
 *
 * THIS IS NOW THE ONE DEFINITION OF struct iovec, which used to live in
 * <sys/socket.h> with a comment saying it had the "sys/uio.h shape". That was
 * true and it was the wrong place: a program that includes only <sys/uio.h>
 * got no iovec at all, and one that includes both would have got two
 * definitions the moment this file appeared. <sys/socket.h> now includes this
 * header, which is what glibc does and is the arrangement that cannot drift.
 *
 * Found attempting busybox on i386: sysklogd/syslogd_and_logger.c writes a log
 * line as a two-element writev so the timestamp and the message reach the
 * socket as ONE datagram.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_UIO_H
#define _CRTL_SYS_UIO_H

#include <stddef.h>
#include <sys/types.h>

#ifndef _CRTL_HAVE_STRUCT_IOVEC
#define _CRTL_HAVE_STRUCT_IOVEC 1
struct iovec {
  void  *iov_base;
  size_t iov_len;
};
#endif

/* The kernel's per-call limit on the vector length. */
#define UIO_MAXIOV 1024

ssize_t readv(int fd, const struct iovec *iov, int iovcnt);
ssize_t writev(int fd, const struct iovec *iov, int iovcnt);
ssize_t preadv(int fd, const struct iovec *iov, int iovcnt, off_t offset);
ssize_t pwritev(int fd, const struct iovec *iov, int iovcnt, off_t offset);

#endif
