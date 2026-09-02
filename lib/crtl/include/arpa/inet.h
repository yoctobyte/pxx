/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_ARPA_INET_H
#define PXX_CRTL_ARPA_INET_H 1

#include <stdint.h>
#include <netinet/in.h>

uint16_t htons(uint16_t hostshort);
uint16_t ntohs(uint16_t netshort);
uint32_t htonl(uint32_t hostlong);
uint32_t ntohl(uint32_t netlong);

/* textual IPv4 conversion — see src/netinet/in.c (AF_INET only, no resolver) */
int inet_aton(const char *s, struct in_addr *out);
in_addr_t inet_addr(const char *s);
int inet_pton(int af, const char *src, void *dst);
const char *inet_ntop(int af, const void *src, char *dst, socklen_t size);
/* inet_ntoa takes its argument BY VALUE, which is why it was absent: the C
   frontend could not pass a 4-byte struct in a register. It can now (measured
   2026-09-02 against a gcc build of the same source, for both a 4-byte and an
   8-byte struct), so the omission is gone rather than merely re-explained.
   The result is a STATIC buffer invalidated by the next call -- glibc's
   contract, and the reason busybox's route.c prints one address per printf. */
char *inet_ntoa(struct in_addr in);

#endif
