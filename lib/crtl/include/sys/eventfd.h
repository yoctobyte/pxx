/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/eventfd.h> -- eventfd(2) and glibc's two read/write helpers.
 * The flags are the open flags of the same names (Linux defines them that way),
 * so they come from <fcntl.h> and stay right on every target.
 */
#ifndef PXX_CRTL_SYS_EVENTFD_H
#define PXX_CRTL_SYS_EVENTFD_H 1

#include <stdint.h>
#include <fcntl.h>

typedef uint64_t eventfd_t;

#define EFD_SEMAPHORE 1
#define EFD_CLOEXEC   O_CLOEXEC
#define EFD_NONBLOCK  O_NONBLOCK

int eventfd(unsigned int initval, int flags);
int eventfd_read(int fd, eventfd_t *value);
int eventfd_write(int fd, eventfd_t value);

#endif
