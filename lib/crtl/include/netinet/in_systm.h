/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/in_systm.h> -- the "network byte order" integer types
 * old BSD networking code declares IP header fields with. dropbear's
 * src/includes.h includes it whenever configure found it.
 */
#ifndef _CRTL_NETINET_IN_SYSTM_H
#define _CRTL_NETINET_IN_SYSTM_H

#include <stdint.h>

typedef uint16_t n_short;
typedef uint32_t n_long;
typedef uint32_t n_time;

#endif
