/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/un.h> -- AF_UNIX addresses.
 *
 * sun_path IS 108 BYTES AND THAT NUMBER IS PART OF THE ABI, not a buffer size
 * this runtime gets to choose: the kernel copies exactly sizeof(struct
 * sockaddr_un) - offsetof(sun_path) and a longer field silently accepts paths
 * it will then truncate. 108 is what Linux has had since 1.0.
 *
 * Found attempting busybox rung 2: sysklogd/syslogd.c binds /dev/log,
 * libbb/xconnect.c carries one inside its len_and_sockaddr.
 */
#ifndef _CRTL_SYS_UN_H
#define _CRTL_SYS_UN_H

#include <sys/socket.h>
#include <string.h>

#define UNIX_PATH_MAX 108

struct sockaddr_un {
  sa_family_t sun_family;
  char sun_path[UNIX_PATH_MAX];
};

/* The length to pass to bind/connect for a PATHNAME socket: the family plus
   the path WITHOUT its NUL. Not sizeof(struct sockaddr_un) -- that also works
   for bind but names the whole 108 bytes, and for an ABSTRACT socket (a
   leading NUL in sun_path) it is wrong in the other direction, since the name
   there runs to the length given rather than to a terminator. */
#define SUN_LEN(p) ((size_t)((char *)&((struct sockaddr_un *)0)->sun_path - (char *)0) \
                    + strlen((p)->sun_path))

#endif
