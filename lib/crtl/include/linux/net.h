/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/net.h>, the socketcall(2) call numbers (SYS_SOCKET ..
 * SYS_SENDMMSG: the first argument of socketcall on the ports that multiplex
 * the socket calls through it, i386 among them), the socket states and
 * NPROTO. A seccomp filter that allows socketcall checks these (dhcpcd's
 * privsep-linux.c). Not <sys/syscall.h>'s SYS_socket: these are upper case
 * and are socketcall's own numbering.
 */
#ifndef _CRTL_LINUX_NET_H
#define _CRTL_LINUX_NET_H
#include <sys/socket.h>

#define NPROTO AF_MAX

#define SYS_SOCKET      1
#define SYS_BIND        2
#define SYS_CONNECT     3
#define SYS_LISTEN      4
#define SYS_ACCEPT      5
#define SYS_GETSOCKNAME 6
#define SYS_GETPEERNAME 7
#define SYS_SOCKETPAIR  8
#define SYS_SEND        9
#define SYS_RECV        10
#define SYS_SENDTO      11
#define SYS_RECVFROM    12
#define SYS_SHUTDOWN    13
#define SYS_SETSOCKOPT  14
#define SYS_GETSOCKOPT  15
#define SYS_SENDMSG     16
#define SYS_RECVMSG     17
#define SYS_ACCEPT4     18
#define SYS_RECVMMSG    19
#define SYS_SENDMMSG    20

typedef enum {
  SS_FREE = 0,
  SS_UNCONNECTED,
  SS_CONNECTING,
  SS_CONNECTED,
  SS_DISCONNECTING
} socket_state;

#define __SO_ACCEPTCON (1 << 16)

#endif
