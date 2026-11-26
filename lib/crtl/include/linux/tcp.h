/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/tcp.h>, the part a user program reads: the TCP socket
 * option numbers, which are <netinet/tcp.h>'s (one list, so the two headers
 * cannot disagree). curl includes this one when configure finds it
 * (HAVE_LINUX_TCP_H), for TCP_KEEPIDLE/KEEPINTVL/KEEPCNT and
 * TCP_FASTOPEN_CONNECT. The kernel's struct tcphdr and struct tcp_info are
 * not here.
 */
#ifndef _CRTL_LINUX_TCP_H
#define _CRTL_LINUX_TCP_H
#include <netinet/tcp.h>
#endif
