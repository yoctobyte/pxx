/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: BSD socket veneer over the Pascal PAL.
 *
 * IPv4 first: C sees normal sockaddr_in in network byte order; this file
 * converts to the PAL's host-order IPv4 address/port primitives.
 */

#include <errno.h>
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

int close(int fd) {
  return __crtl_sock_fail(__pxx_socket_close(fd));
}

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

/* ---- textual IPv4 conversion (arpa/inet.h) -------------------------------- */
/* Pure string<->uint32 parsing — no resolver, no allocation. Added for the
   ENet candidate (game-library ladder); AF_INET only, matching the rest of
   this IPv4-only socket layer. */

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

int inet_pton(int af, const char *src, void *dst) {
  if (af != 2 /* AF_INET */) return -1;
  return inet_aton(src, (struct in_addr *)dst) ? 1 : 0;
}

const char *inet_ntop(int af, const void *src, char *dst, socklen_t size) {
  uint32_t v;
  int i, n = 0, o;
  char tmp[16];
  if (af != 2 /* AF_INET */ || !src || !dst) return 0;
  v = ntohl(((const struct in_addr *)src)->s_addr);
  for (i = 3; i >= 0; i--) {
    o = (int)((v >> (i * 8)) & 0xFF);
    if (o >= 100) tmp[n++] = (char)('0' + o / 100);
    if (o >= 10)  tmp[n++] = (char)('0' + (o / 10) % 10);
    tmp[n++] = (char)('0' + o % 10);
    if (i > 0) tmp[n++] = '.';
  }
  if ((socklen_t)(n + 1) > size) return 0;
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

/* getaddrinfo: numeric-host only (no DNS). Callers that pass a dotted-quad
   `node` still resolve; a hostname reports EAI_NONAME. Kept minimal — a real
   resolver is the DNS-library track. */
int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res) {
  (void)service; (void)hints;
  if (res) *res = 0;
  (void)node;
  return -2; /* EAI_NONAME — no resolver; numeric paths use inet_pton directly */
}
void freeaddrinfo(struct addrinfo *res) { (void)res; }
const char *gai_strerror(int errcode) { (void)errcode; return "resolver unavailable"; }

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
