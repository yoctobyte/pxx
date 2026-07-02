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
