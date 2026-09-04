/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: BSD socket veneer over the Pascal PAL.
 *
 * IPv4 first: C sees normal sockaddr_in in network byte order; this file
 * converts to the PAL's host-order IPv4 address/port primitives.
 *
 * WHY IT LIVES UNDER netinet/ AND NOT sys/, despite implementing <sys/socket.h>.
 * crtl auto-pulls src/<x>.c when <x.h> completes. As src/sys/socket.c this file
 * was pulled the moment <sys/socket.h> finished — which is BEFORE
 * <netinet/in.h> (whose first act is to include <sys/socket.h>) has defined
 * in_addr_t and struct sockaddr_in, and too late to pull them, since that
 * header's guard is already set. Here it is pulled when <netinet/in.h>
 * completes, with every type it needs in scope.
 *
 * As src/socket.c — where it used to be — NO header mapped to it at all
 * (src/arpa/inet.c, src/netinet/in.c and src/sys/socket.c all did not exist),
 * so it was never pulled, every prototype stayed external, and calls fell back
 * to glibc dynamic imports. That worked on glibc and broke everywhere else:
 * bug-cfront-spurious-dt-needed-libc-with-no-imports.
 *
 * src/sys/socket.c is now a small shim that reaches this file for programs
 * including only <sys/socket.h>; see the comment there for why it has to test
 * the guard rather than include unconditionally.
 */

#include <errno.h>
#include <stdio.h>   /* snprintf, for inet_ntoa */
#include <stdlib.h>  /* malloc/free/strtol, for the getaddrinfo result block */
#include <string.h>  /* memcpy/strlen/strncpy */
#include <stddef.h>
#include <stdint.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>

extern int __pxx_socket(int domain, int kind, int proto);
extern int __pxx_setsockopt(int fd, int level, int optname, void *val, int len);
extern int __pxx_bind_ipv4(int fd, unsigned long host, int port);
extern int __pxx_connect_ipv4(int fd, unsigned long host, int port);
extern int __pxx_listen(int fd, int backlog);
extern int __pxx_accept_ipv4(int fd, unsigned long *outHost, int *outPort);
extern long __pxx_send(int fd, const void *buf, int len);
extern long __pxx_recv(int fd, void *buf, int len);
extern long __pxx_sendto_ipv4(int fd, const void *buf, int len, unsigned long host, int port);
extern long __pxx_recvfrom_ipv4(int fd, void *buf, int len, unsigned long *outHost, int *outPort);
extern int __pxx_shutdown(int fd, int how);
extern int __pxx_socket_close(int fd);
extern int __pxx_getsockname_ipv4(int fd, unsigned long *outHost, int *outPort);
extern int __pxx_getpeername_ipv4(int fd, unsigned long *outHost, int *outPort);
extern int __pxx_getsockerror(int fd);

uint16_t htons(uint16_t v) { return (uint16_t)(((v & 0x00ffU) << 8) | ((v & 0xff00U) >> 8)); }
uint16_t ntohs(uint16_t v) { return htons(v); }
uint32_t htonl(uint32_t v) {
  return ((v & 0x000000ffUL) << 24) | ((v & 0x0000ff00UL) << 8) |
         ((v & 0x00ff0000UL) >> 8)  | ((v & 0xff000000UL) >> 24);
}
uint32_t ntohl(uint32_t v) { return htonl(v); }

static int __crtl_sock_fail(int rc) {
  if (rc < 0) {
    errno = -rc;
    return -1;
  }
  return rc;
}

static ssize_t __crtl_sock_fail_long(long rc) {
  if (rc < 0) {
    errno = (int)(-rc);
    return -1;
  }
  return (ssize_t)rc;
}

static int __crtl_sockaddr_in(const struct sockaddr *addr, unsigned long *host, int *port) {
  const struct sockaddr_in *in;
  if (!addr) { errno = EINVAL; return -1; }
  in = (const struct sockaddr_in *)addr;
  if (in->sin_family != AF_INET) { errno = EINVAL; return -1; }
  *host = (unsigned long)ntohl(in->sin_addr.s_addr);
  *port = (int)ntohs(in->sin_port);
  return 0;
}

static void __crtl_fill_sockaddr_in(struct sockaddr *addr, socklen_t *addrlen,
                                    unsigned long host, int port) {
  struct sockaddr_in *in;
  int i;
  if (!addr) return;
  in = (struct sockaddr_in *)addr;
  in->sin_family = AF_INET;
  in->sin_port = htons((uint16_t)port);
  in->sin_addr.s_addr = htonl((uint32_t)host);
  for (i = 0; i < 8; i++) in->sin_zero[i] = 0;
  if (addrlen) *addrlen = sizeof(struct sockaddr_in);
}

int socket(int domain, int type, int protocol) {
  return __crtl_sock_fail(__pxx_socket(domain, type, protocol));
}

int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
  unsigned long host;
  int port;
  (void)addrlen;
  if (__crtl_sockaddr_in(addr, &host, &port) < 0) return -1;
  return __crtl_sock_fail(__pxx_bind_ipv4(sockfd, host, port));
}

int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
  unsigned long host;
  int port;
  (void)addrlen;
  if (__crtl_sockaddr_in(addr, &host, &port) < 0) return -1;
  return __crtl_sock_fail(__pxx_connect_ipv4(sockfd, host, port));
}

int listen(int sockfd, int backlog) {
  return __crtl_sock_fail(__pxx_listen(sockfd, backlog));
}

int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen) {
  unsigned long host;
  int port;
  int fd = __pxx_accept_ipv4(sockfd, &host, &port);
  if (fd < 0) return __crtl_sock_fail(fd);
  __crtl_fill_sockaddr_in(addr, addrlen, host, port);
  return fd;
}

ssize_t send(int sockfd, const void *buf, size_t len, int flags) {
  (void)flags;
  return __crtl_sock_fail_long(__pxx_send(sockfd, buf, (int)len));
}

ssize_t recv(int sockfd, void *buf, size_t len, int flags) {
  (void)flags;
  return __crtl_sock_fail_long(__pxx_recv(sockfd, buf, (int)len));
}

ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen) {
  unsigned long host;
  int port;
  (void)flags;
  (void)addrlen;
  if (__crtl_sockaddr_in(dest_addr, &host, &port) < 0) return -1;
  return __crtl_sock_fail_long(__pxx_sendto_ipv4(sockfd, buf, (int)len, host, port));
}

ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
                 struct sockaddr *src_addr, socklen_t *addrlen) {
  unsigned long host;
  int port;
  long rc;
  (void)flags;
  rc = __pxx_recvfrom_ipv4(sockfd, buf, (int)len, &host, &port);
  if (rc < 0) return __crtl_sock_fail_long(rc);
  __crtl_fill_sockaddr_in(src_addr, addrlen, host, port);
  return rc;
}

int shutdown(int sockfd, int how) {
  return __crtl_sock_fail(__pxx_shutdown(sockfd, how));
}

/* NO `close` here. POSIX has ONE close() over one fd namespace, and it is
   unistd.c's — this file used to define a second body that routed every close in
   the TU through __pxx_socket_close, so whether closing a regular FILE went to
   the file or the socket PAL entry depended on which module was pulled last.
   Found by the C duplicate-definition warning (bug-c-string-h-compiles-stdlib-c-
   twice). On POSIX the two are the same syscall (PalBackendSocketClose calls
   PalBackendClose), so unistd's close is correct for sockets too. On ESP-IDF
   they genuinely differ (lwip_close vs fclose) and neither single body can serve
   both without an fd registry — bug-b-crtl-esp-close-cannot-dispatch-socket-vs-file. */

int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen) {
  return __crtl_sock_fail(__pxx_setsockopt(sockfd, level, optname, (void *)optval, (int)optlen));
}

int getsockopt(int sockfd, int level, int optname, void *optval, socklen_t *optlen) {
  int err;
  (void)level;
  if (optname != SO_ERROR || !optval || !optlen || *optlen < sizeof(int)) {
    errno = EINVAL;
    return -1;
  }
  err = __pxx_getsockerror(sockfd);
  if (err < 0) err = -err;
  *(int *)optval = err;
  *optlen = sizeof(int);
  return 0;
}

int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen) {
  unsigned long host;
  int port;
  int rc = __pxx_getsockname_ipv4(sockfd, &host, &port);
  if (rc < 0) return __crtl_sock_fail(rc);
  __crtl_fill_sockaddr_in(addr, addrlen, host, port);
  return 0;
}

int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen) {
  unsigned long host;
  int port;
  int rc = __pxx_getpeername_ipv4(sockfd, &host, &port);
  if (rc < 0) return __crtl_sock_fail(rc);
  __crtl_fill_sockaddr_in(addr, addrlen, host, port);
  return 0;
}

/* ---- textual IPv4 conversion (arpa/inet.h) -------------------------------- */
/* Pure string<->uint32 parsing — no resolver, no allocation. Added for the
   ENet candidate (game-library ladder); AF_INET only, matching the rest of
   this IPv4-only socket layer. */

/* inet_ntoa(3): the dotted quad for an address held BY VALUE.

   ONE STATIC BUFFER, invalidated by the next call, because that is glibc's
   contract and callers are written against it -- busybox's route.c prints one
   address per printf for exactly this reason. Returning a per-call buffer
   would be kinder and would also be a different function: code that saves the
   pointer and calls again expects the FIRST string to change, and some of it
   compares the two pointers.

   The bytes come out in NETWORK order, low byte first in memory, which is
   what makes this a memcpy-free read of s_addr rather than an ntohl. */
/* The two addresses <netinet/in.h> declares. They are DEFINED here rather than
   left as macros because programs take their address and compare against them
   by pointer; a macro-only spelling compiles and then links against nothing. */
const struct in6_addr in6addr_any = IN6ADDR_ANY_INIT;
const struct in6_addr in6addr_loopback = IN6ADDR_LOOPBACK_INIT;

char *inet_ntoa(struct in_addr in) {
  static char buf[16];
  const unsigned char *p = (const unsigned char *)&in.s_addr;
  snprintf(buf, sizeof buf, "%u.%u.%u.%u",
           (unsigned)p[0], (unsigned)p[1], (unsigned)p[2], (unsigned)p[3]);
  return buf;
}

int inet_aton(const char *s, struct in_addr *out) {
  unsigned long parts[4];
  int np = 0;
  if (!s || !out) return 0;
  for (;;) {
    unsigned long v = 0;
    int any = 0;
    while (*s >= '0' && *s <= '9') { v = v * 10UL + (unsigned long)(*s - '0'); s++; any = 1; if (v > 255UL) return 0; }
    if (!any || np >= 4) return 0;
    parts[np++] = v;
    if (*s == '.') { s++; continue; }
    break;
  }
  if (*s != 0 || np != 4) return 0;
  out->s_addr = htonl((uint32_t)((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]));
  return 1;
}

in_addr_t inet_addr(const char *s) {
  struct in_addr a;
  if (!inet_aton(s, &a)) return 0xFFFFFFFFU;   /* INADDR_NONE */
  return a.s_addr;
}

/* ---- IPv6 presentation <-> binary -------------------------------------
   ADDED BECAUSE nslookup's AAAA BRANCH WAS DEAD WITHOUT IT, and dead in the
   worst way: inet_ntop(AF_INET6, ...) returned NULL, the caller printed its
   UNINITIALISED buffer, and what came out was the PREVIOUS record's IPv4
   address -- a plausible wrong answer with no error anywhere. The stale-stack
   read is why this is a bug rather than a missing feature.

   THE OUTPUT FORM IS RFC 5952 AND IT IS NOT A FREE CHOICE. Lowercase hex, no
   leading zeros, and the LONGEST run of zero groups replaced by "::" with the
   LEFTMOST winning a tie -- because two spellings of one address break every
   textual comparison a program does with them. The run must be at least two
   groups: "::" standing for a single zero group is legal to parse and illegal
   to emit, and glibc emits the same. */

static int inet_pton6(const char *src, unsigned char *dst) {
  unsigned char tmp[16], *tp, *endp, *colonp;
  const char *curtok;
  int ch, seen_xdigits;
  unsigned int val;

  memset(tp = tmp, 0, sizeof tmp);
  endp = tp + sizeof tmp;
  colonp = 0;
  if (*src == ':' && *++src != ':') return 0;
  curtok = src;
  seen_xdigits = 0;
  val = 0;
  while ((ch = *src++) != 0) {
    int digit = -1;
    if (ch >= '0' && ch <= '9') digit = ch - '0';
    else if (ch >= 'a' && ch <= 'f') digit = ch - 'a' + 10;
    else if (ch >= 'A' && ch <= 'F') digit = ch - 'A' + 10;
    if (digit >= 0) {
      val <<= 4;
      val |= (unsigned)digit;
      if (++seen_xdigits > 4) return 0;
      continue;
    }
    if (ch == ':') {
      curtok = src;
      if (!seen_xdigits) {
        if (colonp) return 0;      /* only one "::" is allowed */
        colonp = tp;
        continue;
      } else if (*src == '\0') {
        return 0;                  /* a trailing single ':' is not an address */
      }
      if (tp + 2 > endp) return 0;
      *tp++ = (unsigned char)(val >> 8);
      *tp++ = (unsigned char)(val & 0xff);
      seen_xdigits = 0;
      val = 0;
      continue;
    }
    /* A TRAILING DOTTED-QUAD IS PART OF THE SYNTAX, not a special case:
       "::ffff:192.0.2.1" is how an IPv4-mapped address is written. */
    if (ch == '.' && (tp + 4) <= endp) {
      struct in_addr v4;
      if (!inet_aton(curtok, &v4)) return 0;
      memcpy(tp, &v4.s_addr, 4);
      tp += 4;
      seen_xdigits = 0;
      break;
    }
    return 0;
  }
  if (seen_xdigits) {
    if (tp + 2 > endp) return 0;
    *tp++ = (unsigned char)(val >> 8);
    *tp++ = (unsigned char)(val & 0xff);
  }
  if (colonp != 0) {
    /* Slide everything after the "::" down to the end; the gap it leaves is
       already zero. A zero-length gap means the address was written with
       "::" where it was not needed, which is an error. */
    int n = (int)(tp - colonp), i;
    if (tp == endp) return 0;
    for (i = 1; i <= n; i++) {
      endp[-i] = colonp[n - i];
      colonp[n - i] = 0;
    }
    tp = endp;
  }
  if (tp != endp) return 0;
  memcpy(dst, tmp, 16);
  return 1;
}

static const char *inet_ntop6(const unsigned char *src, char *dst, socklen_t size) {
  char tmp[46], *tp;
  unsigned int words[8];
  int i, best = -1, bestlen = 0, cur = -1, curlen = 0;

  for (i = 0; i < 8; i++)
    words[i] = ((unsigned)src[i * 2] << 8) | (unsigned)src[i * 2 + 1];
  for (i = 0; i < 8; i++) {
    if (words[i] == 0) {
      if (cur < 0) { cur = i; curlen = 1; } else curlen++;
      /* `>' AND NOT `>=' IS WHAT MAKES THE LEFTMOST RUN WIN A TIE, which
         RFC 5952 requires and which is the whole reason two implementations
         can otherwise print one address two ways. */
      if (curlen > bestlen) { best = cur; bestlen = curlen; }
    } else {
      cur = -1; curlen = 0;
    }
  }
  if (bestlen < 2) { best = -1; bestlen = 0; }

  tp = tmp;
  for (i = 0; i < 8; i++) {
    if (best >= 0 && i >= best && i < best + bestlen) {
      if (i == best) *tp++ = ':';
      continue;
    }
    if (i != 0) *tp++ = ':';
    /* The last two groups print as a dotted quad for the v4-mapped and
       v4-compatible forms, which is what glibc does and what every tool that
       reads this output expects. */
    if (i == 6 && best == 0 &&
        (bestlen == 6 || (bestlen == 7 && words[7] != 0x0001) ||
         (bestlen == 5 && words[5] == 0xffff))) {
      const unsigned char *q = src + 12;
      int k;
      for (k = 0; k < 4; k++) {
        int o = q[k];
        if (o >= 100) *tp++ = (char)('0' + o / 100);
        if (o >= 10)  *tp++ = (char)('0' + (o / 10) % 10);
        *tp++ = (char)('0' + o % 10);
        if (k < 3) *tp++ = '.';
      }
      i = 7;
      break;
    }
    {
      static const char hex[] = "0123456789abcdef";
      unsigned int w = words[i];
      int started = 0, sh;
      for (sh = 12; sh >= 0; sh -= 4) {
        int d = (int)((w >> sh) & 0xf);
        if (d != 0 || started || sh == 0) { *tp++ = hex[d]; started = 1; }
      }
    }
  }
  if (best >= 0 && best + bestlen == 8) *tp++ = ':';
  *tp = '\0';
  if ((socklen_t)(tp - tmp + 1) > size) { errno = ENOSPC; return 0; }
  memcpy(dst, tmp, (size_t)(tp - tmp + 1));
  return dst;
}

int inet_pton(int af, const char *src, void *dst) {
  if (af == 2 /* AF_INET */)
    return inet_aton(src, (struct in_addr *)dst) ? 1 : 0;
  if (af == 10 /* AF_INET6 */)
    return inet_pton6(src, (unsigned char *)dst);
  /* AN UNKNOWN FAMILY IS -1 WITH EAFNOSUPPORT, NOT 0. The two answers mean
     different things -- 0 is "that string is not an address of this family"
     and -1 is "I do not know this family" -- and a caller that treats them
     alike reports a malformed address for a family it never supported. */
  errno = EAFNOSUPPORT;
  return -1;
}

const char *inet_ntop(int af, const void *src, char *dst, socklen_t size) {
  uint32_t v;
  int i, n = 0, o;
  char tmp[16];
  if (!src || !dst) { errno = EAFNOSUPPORT; return 0; }
  if (af == 10 /* AF_INET6 */) return inet_ntop6((const unsigned char *)src, dst, size);
  if (af != 2 /* AF_INET */) { errno = EAFNOSUPPORT; return 0; }
  v = ntohl(((const struct in_addr *)src)->s_addr);
  for (i = 3; i >= 0; i--) {
    o = (int)((v >> (i * 8)) & 0xFF);
    if (o >= 100) tmp[n++] = (char)('0' + o / 100);
    if (o >= 10)  tmp[n++] = (char)('0' + (o / 10) % 10);
    tmp[n++] = (char)('0' + o % 10);
    if (i > 0) tmp[n++] = '.';
  }
  if ((socklen_t)(n + 1) > size) { errno = ENOSPC; return 0; }
  for (i = 0; i < n; i++) dst[i] = tmp[i];
  dst[n] = 0;
  return dst;
}

/* No resolver in the libc-free runtime: gethostby* report not-found. Numeric
   addresses go through inet_aton/inet_pton above (ENet tries those first). */
struct hostent *gethostbyname(const char *name) { (void)name; return 0; }
struct hostent *gethostbyaddr(const void *addr, socklen_t len, int type) {
  (void)addr; (void)len; (void)type; return 0;
}

/* ---- getaddrinfo / getnameinfo -------------------------------------------
   NUMERIC ONLY, AND THAT IS THE WHOLE CONTRACT. There is no DNS client in this
   runtime and no NSS to load one from, so a hostname is EAI_NONAME here and a
   reverse lookup never happens. What DOES work is everything busybox's
   libbb/xconnect.c needs to reach an address it was handed literally: a dotted
   quad, a NULL node under AI_PASSIVE, a numeric or /etc/services port name,
   and the sockaddr-to-string direction.

   THE PREVIOUS BODY RETURNED EAI_NONAME FOR EVERYTHING while its comment said
   "callers that pass a dotted-quad node still resolve". The comment described
   the intent and the code never did it; the two disagreed and the comment was
   the one worth keeping, so this implements it. Anything that called
   getaddrinfo with an IP literal -- which is every busybox networking applet
   under `-n', and every one of them when given an address rather than a name
   -- got "bad address" from a resolver that had not looked.

   IPv4 ONLY. An AF_INET6 hint is EAI_FAMILY rather than a v6 sockaddr this
   socket layer could not then connect. Declaring the type is not a claim that
   it works, and returning a struct nothing can use would be exactly that. */

/* One malloc per result: the addrinfo, its sockaddr and its canonname live in
   a single block, so freeaddrinfo frees one pointer per node and cannot
   half-free a partially built list. */
struct pxx_ai_block {
  struct addrinfo ai;
  struct sockaddr_in sa;
  char canon[256];
};

static int ai_port(const char *service, const struct addrinfo *hints,
                   unsigned short *out) {
  const char *q;
  long v;
  struct servent *se;
  int numeric_only, dgram;

  *out = 0;
  if (!service || !*service) return 0;

  /* all digits -> a port number, whatever the flags say */
  for (q = service; *q; q++)
    if (*q < '0' || *q > '9') break;
  if (*q == 0) {
    v = strtol(service, 0, 10);
    if (v < 0 || v > 65535) return EAI_SERVICE;
    *out = (unsigned short)v;
    return 0;
  }

  numeric_only = hints && (hints->ai_flags & AI_NUMERICSERV);
  if (numeric_only) return EAI_NONAME;

  dgram = hints && hints->ai_socktype == SOCK_DGRAM;
  se = getservbyname(service, dgram ? "udp" : "tcp");
  if (!se) return EAI_SERVICE;
  /* s_port is ALREADY in network order -- see src/netdb.c. Converting it back
     here rather than storing it swapped is the one place this is easy to get
     wrong twice and have it cancel out. */
  *out = ntohs((unsigned short)se->s_port);
  return 0;
}

int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res) {
  struct pxx_ai_block *b;
  struct in_addr addr;
  unsigned short port;
  int fam, rc;

  if (!res) return EAI_SYSTEM;
  *res = 0;
  if (!node && !service) return EAI_NONAME;

  fam = hints ? hints->ai_family : AF_UNSPEC;
  if (fam != AF_UNSPEC && fam != AF_INET) return EAI_FAMILY;

  rc = ai_port(service, hints, &port);
  if (rc != 0) return rc;

  if (!node) {
    /* AI_PASSIVE means "an address to bind to": the wildcard. Without it the
       caller wants a destination, and the destination for "no host" is the
       loopback -- that asymmetry is getaddrinfo's, not ours. */
    addr.s_addr = (hints && (hints->ai_flags & AI_PASSIVE))
                    ? htonl(INADDR_ANY) : htonl(INADDR_LOOPBACK);
  } else if (inet_pton(AF_INET, node, &addr) != 1) {
    return EAI_NONAME;    /* a NAME, and there is no resolver -- see above */
  }

  b = (struct pxx_ai_block *)malloc(sizeof(*b));
  if (!b) return EAI_MEMORY;
  memset(b, 0, sizeof(*b));

  b->sa.sin_family = AF_INET;
  b->sa.sin_port = htons(port);
  b->sa.sin_addr = addr;

  b->ai.ai_family = AF_INET;
  b->ai.ai_socktype = hints ? hints->ai_socktype : 0;
  b->ai.ai_protocol = hints ? hints->ai_protocol : 0;
  b->ai.ai_flags = hints ? hints->ai_flags : 0;
  b->ai.ai_addrlen = (socklen_t)sizeof(b->sa);
  b->ai.ai_addr = (struct sockaddr *)&b->sa;
  b->ai.ai_next = 0;
  if (hints && (hints->ai_flags & AI_CANONNAME) && node) {
    /* The canonical name of a numeric address is the numeric address. Nothing
       here can produce anything better, and leaving it NULL makes a caller
       that prints it print nothing. */
    strncpy(b->canon, node, sizeof(b->canon) - 1);
    b->ai.ai_canonname = b->canon;
  }
  *res = &b->ai;
  return 0;
}

void freeaddrinfo(struct addrinfo *res) {
  struct addrinfo *next;
  /* Every node in a list this file built is the head of its own block, so the
     addrinfo pointer IS the malloc pointer. A list from anywhere else would
     not be, which is why nothing else builds one. */
  while (res) {
    next = res->ai_next;
    free(res);
    res = next;
  }
}

const char *gai_strerror(int errcode) {
  switch (errcode) {
    case 0:             return "Success";
    case EAI_BADFLAGS:  return "Bad value for ai_flags";
    case EAI_NONAME:    return "Name or service not known";
    case EAI_AGAIN:     return "Temporary failure in name resolution";
    case EAI_FAIL:      return "Non-recoverable failure in name resolution";
    case EAI_FAMILY:    return "ai_family not supported";
    case EAI_SOCKTYPE:  return "ai_socktype not supported";
    case EAI_SERVICE:   return "Servname not supported for ai_socktype";
    case EAI_MEMORY:    return "Memory allocation failure";
    case EAI_SYSTEM:    return "System error";
    case EAI_OVERFLOW:  return "Argument buffer overflow";
    default:            return "Unknown error";
  }
}

int getnameinfo(const struct sockaddr *sa, socklen_t salen,
                char *host, socklen_t hostlen,
                char *serv, socklen_t servlen, int flags) {
  const struct sockaddr_in *in = (const struct sockaddr_in *)sa;
  char buf[INET_ADDRSTRLEN];
  struct servent *se;
  unsigned short port;
  size_t n;

  if (!sa) return EAI_FAMILY;
  if (sa->sa_family != AF_INET) return EAI_FAMILY;
  if (salen < (socklen_t)sizeof(struct sockaddr_in)) return EAI_FAMILY;

  if (host && hostlen > 0) {
    /* NI_NAMEREQD MUST FAIL. A caller that asked for a name and would rather
       have nothing than a number is asking a question this runtime cannot
       answer, and handing back the dotted quad answers a DIFFERENT question
       while looking like success -- busybox's xmalloc_sockaddr2host wants the
       NULL. */
    if (flags & NI_NAMEREQD) return EAI_NONAME;
    if (!inet_ntop(AF_INET, &in->sin_addr, buf, sizeof(buf))) return EAI_FAIL;
    n = strlen(buf);
    if (n + 1 > (size_t)hostlen) return EAI_OVERFLOW;
    memcpy(host, buf, n + 1);
  }

  if (serv && servlen > 0) {
    port = ntohs(in->sin_port);        /* for printing: host order */
    se = 0;
    /* getservbyport takes NETWORK order -- the same convention servent.s_port
       stores -- so the field goes in unconverted rather than round-tripped
       through `port'. Writing htons(ntohs(x)) here would be correct and would
       also read as if one of the two were the fix for something. */
    if (!(flags & NI_NUMERICSERV))
      se = getservbyport((int)in->sin_port, (flags & NI_DGRAM) ? "udp" : "tcp");
    if (se && se->s_name) {
      n = strlen(se->s_name);
      if (n + 1 > (size_t)servlen) return EAI_OVERFLOW;
      memcpy(serv, se->s_name, n + 1);
    } else {
      /* snprintf would be the obvious spelling, but it TRUNCATES, and a
         truncated port is a different port. Format into a local and check. */
      char pbuf[8];
      int k = 0, i;
      unsigned short v = port;
      if (v == 0) pbuf[k++] = '0';
      while (v) { pbuf[k++] = (char)('0' + v % 10); v = (unsigned short)(v / 10); }
      if ((size_t)k + 1 > (size_t)servlen) return EAI_OVERFLOW;
      for (i = 0; i < k; i++) serv[i] = pbuf[k - 1 - i];
      serv[k] = 0;
    }
  }
  return 0;
}

/* sendmsg/recvmsg: scatter/gather over the PAL's single-buffer send/recv.
   The PAL has no native iovec syscall, so concatenate: sendmsg walks the iovec
   and sends each fragment in order; recvmsg fills each fragment in turn. Good
   for the stream/datagram uses ENet and friends make (a small iovec of a
   header + payload); msg_name (address) and control data are ignored (crtl is
   connected-socket / IPv4-only at this layer). */
ssize_t sendmsg(int sockfd, const struct msghdr *msg, int flags) {
  ssize_t total = 0, r;
  size_t k;
  if (!msg) return -1;
  for (k = 0; k < msg->msg_iovlen; k++) {
    struct iovec *v = &msg->msg_iov[k];
    if (v->iov_len == 0) continue;
    r = send(sockfd, v->iov_base, v->iov_len, flags);
    if (r < 0) return total > 0 ? total : r;
    total += r;
    if ((size_t)r < v->iov_len) break;   /* short write: stop, report progress */
  }
  return total;
}

ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags) {
  ssize_t total = 0, r;
  size_t k;
  if (!msg) return -1;
  for (k = 0; k < msg->msg_iovlen; k++) {
    struct iovec *v = &msg->msg_iov[k];
    if (v->iov_len == 0) continue;
    r = recv(sockfd, v->iov_base, v->iov_len, flags);
    if (r < 0) return total > 0 ? total : r;
    total += r;
    if ((size_t)r < v->iov_len) break;   /* short read: no more data queued */
  }
  msg->msg_flags = 0;
  return total;
}

/* poll: the PAL has no readiness primitive yet, so this is a minimal
   optimistic stub — it reports every requested fd as ready for the events the
   caller asked about (POLLIN|POLLOUT), which lets a blocking-socket event loop
   proceed (the following blocking send/recv is what actually waits). A real
   readiness poll is a PAL feature (feature-dns-resolver-library / a PAL poll
   ticket); until then non-blocking callers must not rely on this to gate. */
int poll(struct pollfd *fds, nfds_t nfds, int timeout) {
  nfds_t i;
  int ready = 0;
  (void)timeout;
  if (!fds) return 0;
  for (i = 0; i < nfds; i++) {
    fds[i].revents = (short)(fds[i].events & (POLLIN | POLLOUT));
    if (fds[i].revents) ready++;
  }
  return ready;
}
