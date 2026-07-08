/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_ARPA_INET_H
#define PXX_CRTL_ARPA_INET_H 1

#include <stdint.h>
#include <netinet/in.h>

uint16_t htons(uint16_t hostshort);
uint16_t ntohs(uint16_t netshort);
uint32_t htonl(uint32_t hostlong);
uint32_t ntohl(uint32_t netlong);

/* textual IPv4 conversion — see src/socket.c (AF_INET only, no resolver) */
int inet_aton(const char *s, struct in_addr *out);
in_addr_t inet_addr(const char *s);
int inet_pton(int af, const char *src, void *dst);
const char *inet_ntop(int af, const void *src, char *dst, socklen_t size);
/* inet_ntoa(struct in_addr) omitted: needs 4-byte struct-by-value passing
   (bug-c-small-struct-byval-param); ENet uses the pointer-based inet_* only. */

#endif
