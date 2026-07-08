/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_NETDB_H
#define PXX_CRTL_NETDB_H 1

#include <sys/socket.h>
#include <netinet/in.h>

struct hostent {
  char  *h_name;
  char **h_aliases;
  int    h_addrtype;
  int    h_length;
  char **h_addr_list;
};
#define h_addr h_addr_list[0]

struct addrinfo {
  int              ai_flags;
  int              ai_family;
  int              ai_socktype;
  int              ai_protocol;
  socklen_t        ai_addrlen;
  struct sockaddr *ai_addr;
  char            *ai_canonname;
  struct addrinfo *ai_next;
};

#define AI_PASSIVE     0x0001
#define AI_CANONNAME   0x0002
#define AI_NUMERICHOST 0x0004
#define AI_NUMERICSERV 0x0400

#define EAI_NONAME  -2
#define EAI_FAIL    -4
#define EAI_FAMILY  -6
#define EAI_MEMORY -10

struct hostent *gethostbyname(const char *name);
struct hostent *gethostbyaddr(const void *addr, socklen_t len, int type);
int  getaddrinfo(const char *node, const char *service,
                 const struct addrinfo *hints, struct addrinfo **res);
void freeaddrinfo(struct addrinfo *res);
const char *gai_strerror(int errcode);

#endif
