/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_NETINET_IN_H
#define PXX_CRTL_NETINET_IN_H 1

#include <stdint.h>
#include <sys/socket.h>

/* Byte-order helpers. Implemented in socket.c and also declared by
   <arpa/inet.h>; glibc's <netinet/in.h> declares them too, and network code
   routinely includes only this header and expects htons() to be there.
   Duplicate matching declarations across the two headers are fine in C. */
uint16_t htons(uint16_t hostshort);
uint16_t ntohs(uint16_t netshort);
uint32_t htonl(uint32_t hostlong);
uint32_t ntohl(uint32_t netlong);

typedef uint16_t in_port_t;
typedef uint32_t in_addr_t;

struct in_addr {
  in_addr_t s_addr;
};

struct sockaddr_in {
  sa_family_t sin_family;
  in_port_t sin_port;
  struct in_addr sin_addr;
  unsigned char sin_zero[8];
};

#define IPPROTO_IP 0
#define IPPROTO_TCP 6
#define IPPROTO_UDP 17

#define INADDR_ANY 0x00000000U
#define INADDR_LOOPBACK 0x7F000001U
#define INADDR_BROADCAST 0xFFFFFFFFU

#endif
