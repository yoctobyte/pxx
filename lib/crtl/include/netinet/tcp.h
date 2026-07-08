/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_NETINET_TCP_H
#define PXX_CRTL_NETINET_TCP_H 1

/* TCP-level socket options (setsockopt with level = IPPROTO_TCP). Only the
   handful real crtl candidates use are defined; values match Linux. */
#define TCP_NODELAY 1
#define TCP_MAXSEG 2
#define TCP_CORK 3
#define TCP_KEEPIDLE 4
#define TCP_KEEPINTVL 5
#define TCP_KEEPCNT 6

#endif
