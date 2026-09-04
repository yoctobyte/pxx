/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_SOCKET_H
#define PXX_CRTL_SYS_SOCKET_H 1

#include <stddef.h>
#include <sys/types.h>

#include <sys/_types.h>
typedef __socklen_t socklen_t;
typedef unsigned short sa_family_t;

struct sockaddr {
  sa_family_t sa_family;
  char sa_data[14];
};

#define AF_UNSPEC 0
#define AF_UNIX 1        /* == AF_LOCAL; busybox names it AF_UNIX */
#define AF_LOCAL AF_UNIX
#define AF_INET 2
#define AF_INET6 10

#define AF_NETLINK 16
#define AF_PACKET 17

#define PF_UNSPEC AF_UNSPEC
#define PF_INET AF_INET
#define PF_INET6 AF_INET6
#define PF_NETLINK AF_NETLINK
#define PF_PACKET AF_PACKET

#define SOCK_STREAM 1
#define SOCK_DGRAM 2
#define SOCK_RDM 4
#define SOCK_SEQPACKET 5
#define SOCK_RAW 3
#define SOCK_PACKET 10   /* obsolete linux-only type, still asked for */

/* Type-field FLAGS, or-ed into the type argument of socket()/socketpair()/
   accept4(). Same bit values as O_NONBLOCK and O_CLOEXEC because the kernel
   reuses them, and like those two they are NOT uniform: arm and arm64 keep
   asm-generic's O_NONBLOCK, so these are uniform on every target we build for
   and the split that <fcntl.h> needs does not apply here. */
#define SOCK_NONBLOCK 00004000
#define SOCK_CLOEXEC  02000000

#define SOL_SOCKET 1

/* THE OTHER setsockopt LEVELS, from this box's bits/socket.h. They matter more
   than they look: a missing one is not a compile error under pxx -- an
   undeclared identifier used as a value becomes 0 with a warning
   (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error) --
   and level 0 is SOL_IP, a real level that accepts real options. Measured
   2026-09-02: busybox's udhcp client compiled with SOL_PACKET, AF_PACKET and
   PF_PACKET all silently 0, which is a setsockopt on the IP level and a socket
   in AF_UNSPEC. Nothing about that fails at build time. */
#define SOL_IP 0
#define SOL_RAW 255
#define SOL_PACKET 263
#define SOL_NETLINK 270
/* SOL_TCP / SOL_UDP / SOL_IPV6 are NOT here. glibc puts each beside its own
   protocol (<netinet/tcp.h>, <netinet/udp.h>, <netinet/in.h>), nothing in this
   tree reaches for them, and a constant no call site passes is a promise this
   runtime has not been asked to keep -- the same rule the SO_ block above
   states. Adding one costs a line; getting its NUMBER wrong costs a silent
   setsockopt on the wrong level. */

/* SOL_PACKET options (linux/if_packet.h). Only the ones a program in this
   tree reaches; the rest are absent for the reason the SO_ block above gives. */
#define PACKET_ADD_MEMBERSHIP 1
#define PACKET_DROP_MEMBERSHIP 2
#define PACKET_AUXDATA 8

/* THE SO_ NAMES, transcribed from this box's asm-generic/socket.h BY SCRIPT.
   Eighty-one numbers is the population where one recalled digit sets a
   DIFFERENT option, and setsockopt does not reject an unknown-to-you-but-real
   name -- SO_BROADCAST(6) mistyped as SO_DONTROUTE(5) succeeds and the
   broadcast send then fails much later with EACCES.

   asm-generic is the table every target pxx builds for uses; only alpha,
   mips, parisc and sparc renumber these, and pxx targets none of them. Five of
   these names were here already, hand-written and correct; the rest were
   simply absent, so SO_BROADCAST in libbb/xconnect.c became an undeclared
   identifier treated as 0 -- which is not an option at all, and setsockopt
   would have been asked to set option zero.

   The _OLD/_NEW pairs are the kernel's own y2038 split; SO_RCVTIMEO and
   SO_SNDTIMEO below resolve to whichever the target's word size wants, as
   glibc does. */
#define SO_DEBUG                         1
#define SO_REUSEADDR                     2
#define SO_TYPE                          3
#define SO_ERROR                         4
#define SO_DONTROUTE                     5
#define SO_BROADCAST                     6
#define SO_SNDBUF                        7
#define SO_RCVBUF                        8
#define SO_SNDBUFFORCE                   32
#define SO_RCVBUFFORCE                   33
#define SO_KEEPALIVE                     9
#define SO_OOBINLINE                     10
#define SO_NO_CHECK                      11
#define SO_PRIORITY                      12
#define SO_LINGER                        13
#define SO_BSDCOMPAT                     14
#define SO_REUSEPORT                     15
#define SO_PASSCRED                      16
#define SO_PEERCRED                      17
#define SO_RCVLOWAT                      18
#define SO_SNDLOWAT                      19
#define SO_RCVTIMEO_OLD                  20
#define SO_SNDTIMEO_OLD                  21
#define SO_SECURITY_AUTHENTICATION       22
#define SO_SECURITY_ENCRYPTION_TRANSPORT 23
#define SO_SECURITY_ENCRYPTION_NETWORK   24
#define SO_BINDTODEVICE                  25
#define SO_ATTACH_FILTER                 26
#define SO_DETACH_FILTER                 27
#define SO_PEERNAME                      28
#define SO_ACCEPTCONN                    30
#define SO_PEERSEC                       31
#define SO_PASSSEC                       34
#define SO_MARK                          36
#define SO_PROTOCOL                      38
#define SO_DOMAIN                        39
#define SO_RXQ_OVFL                      40
#define SO_WIFI_STATUS                   41
#define SO_PEEK_OFF                      42
#define SO_NOFCS                         43
#define SO_LOCK_FILTER                   44
#define SO_SELECT_ERR_QUEUE              45
#define SO_BUSY_POLL                     46
#define SO_MAX_PACING_RATE               47
#define SO_BPF_EXTENSIONS                48
#define SO_INCOMING_CPU                  49
#define SO_ATTACH_BPF                    50
#define SO_ATTACH_REUSEPORT_CBPF         51
#define SO_ATTACH_REUSEPORT_EBPF         52
#define SO_CNX_ADVICE                    53
#define SO_MEMINFO                       55
#define SO_INCOMING_NAPI_ID              56
#define SO_COOKIE                        57
#define SO_PEERGROUPS                    59
#define SO_ZEROCOPY                      60
#define SO_TXTIME                        61
#define SO_BINDTOIFINDEX                 62
#define SO_TIMESTAMP_OLD                 29
#define SO_TIMESTAMPNS_OLD               35
#define SO_TIMESTAMPING_OLD              37
#define SO_TIMESTAMP_NEW                 63
#define SO_TIMESTAMPNS_NEW               64
#define SO_TIMESTAMPING_NEW              65
#define SO_RCVTIMEO_NEW                  66
#define SO_SNDTIMEO_NEW                  67
#define SO_DETACH_REUSEPORT_BPF          68
#define SO_PREFER_BUSY_POLL              69
#define SO_BUSY_POLL_BUDGET              70
#define SO_NETNS_COOKIE                  71
#define SO_BUF_LOCK                      72
#define SO_RESERVE_MEM                   73
#define SO_TXREHASH                      74
#define SO_RCVMARK                       75
#define SO_PASSPIDFD                     76
#define SO_PEERPIDFD                     77
#define SO_DEVMEM_LINEAR                 78
#define SO_DEVMEM_DMABUF                 79
#define SO_DEVMEM_DONTNEED               80
#define SO_RCVPRIORITY                   82
#define SO_PASSRIGHTS                    83
#define SO_INQ                           84

/* The y2038 aliases. On a 64-bit target the _OLD forms already carry a 64-bit
   timeval, so they ARE the current ones; on a 32-bit target the kernel offers
   _NEW for the 64-bit struct. This runtime marshals timeouts as native words,
   so it follows the same rule glibc does. */
#if defined(__LP64__) || defined(_LP64)
# define SO_RCVTIMEO SO_RCVTIMEO_OLD
# define SO_SNDTIMEO SO_SNDTIMEO_OLD
# define SO_TIMESTAMP SO_TIMESTAMP_OLD
#else
# define SO_RCVTIMEO SO_RCVTIMEO_NEW
# define SO_SNDTIMEO SO_SNDTIMEO_NEW
# define SO_TIMESTAMP SO_TIMESTAMP_NEW
#endif

#define MSG_OOB 1
#define MSG_PEEK 2
#define MSG_TRUNC 0x20
#define MSG_DONTWAIT 0x40
#define MSG_NOSIGNAL 0x4000
#define MSG_MAXIOVLEN 16

/* Scatter/gather I/O. struct iovec USED to be defined here, with a comment
   saying it had "the sys/uio.h shape"; that was true and it was the wrong
   place, because a program including only <sys/uio.h> then got no iovec at
   all. It lives in <sys/uio.h> now -- one definition, included from here the
   way glibc's <sys/socket.h> includes it. */
#include <sys/uio.h>

struct msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  size_t msg_iovlen;
  void *msg_control;
  size_t msg_controllen;
  int msg_flags;
};

/* ANCILLARY DATA -- struct cmsghdr and the CMSG_* walkers.
 *
 * busybox's udhcp client reads SOL_PACKET/PACKET_AUXDATA off a recvmsg control
 * buffer and could not be compiled without them; nothing else in this runtime
 * had needed a control message before.
 *
 * cmsg_len is size_t, NOT socklen_t. POSIX says socklen_t and glibc uses
 * size_t on 64-bit Linux, and the kernel writes the field -- so the wrong one
 * here does not produce a slower program, it produces a walker that reads the
 * length out of the top half of a 64-bit field. Verified against glibc:
 * sizeof(struct cmsghdr) == 16 and CMSG_DATA at offset 16 on x86-64,
 * 12 and 12 on i386.
 *
 * The macros are glibc's, spelled out rather than approximated. CMSG_LEN and
 * CMSG_SPACE differ ONLY in whether the payload is aligned -- LEN is what goes
 * in cmsg_len (header, aligned, plus the exact payload), SPACE is what the
 * buffer must hold (both aligned). Swapping them compiles, runs, and truncates
 * the last control message. */
struct cmsghdr {
  size_t cmsg_len;
  int    cmsg_level;
  int    cmsg_type;
};

#define CMSG_ALIGN(len) \
  (((len) + sizeof(size_t) - 1) & (size_t)~(sizeof(size_t) - 1))
#define CMSG_DATA(cmsg)  ((unsigned char *)((struct cmsghdr *)(cmsg) + 1))
#define CMSG_LEN(len)    (CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
#define CMSG_SPACE(len)  (CMSG_ALIGN(len) + CMSG_ALIGN(sizeof(struct cmsghdr)))
#define CMSG_FIRSTHDR(mhdr) \
  ((size_t)(mhdr)->msg_controllen >= sizeof(struct cmsghdr) \
     ? (struct cmsghdr *)(mhdr)->msg_control : (struct cmsghdr *)0)
/* Padding between a message's payload and the next header. glibc exports this
   as __CMSG_PADDING and __cmsg_nxthdr is written in terms of it; kept because
   the alternative spelling (CMSG_ALIGN(len) - len) is the same value written
   twice. */
#define __CMSG_PADDING(len) \
  ((sizeof(size_t) - ((len) & (sizeof(size_t) - 1))) & (sizeof(size_t) - 1))

/* A FUNCTION, as in glibc, and for the reason glibc gives: the bounds check
   below reads `cmsg->cmsg_len' three times and `mhdr' twice, and a macro doing
   that re-evaluates both. */
struct cmsghdr *__cmsg_nxthdr(struct msghdr *mhdr, struct cmsghdr *cmsg);
#define CMSG_NXTHDR(mhdr, cmsg) __cmsg_nxthdr(mhdr, cmsg)

#define SHUT_RD 0
#define SHUT_WR 1
#define SHUT_RDWR 2

int socket(int domain, int type, int protocol);
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int listen(int sockfd, int backlog);
int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
ssize_t send(int sockfd, const void *buf, size_t len, int flags);
ssize_t recv(int sockfd, void *buf, size_t len, int flags);
ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen);
ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
                 struct sockaddr *src_addr, socklen_t *addrlen);
int shutdown(int sockfd, int how);
int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
int getsockopt(int sockfd, int level, int optname, void *optval, socklen_t *optlen);
int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
/* getpeername(2). Same shape as getsockname and, like it, IPv4 only for now:
   the PAL entry behind it parses an AF_INET sockaddr, so a v6 peer comes back
   as 0.0.0.0:0 rather than as an error. That limit is the socket layer's, not
   this declaration's. */
int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
ssize_t sendmsg(int sockfd, const struct msghdr *msg, int flags);
ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags);

#endif
