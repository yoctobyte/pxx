/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_POLL_H
#define PXX_CRTL_POLL_H 1

typedef unsigned long nfds_t;

struct pollfd {
  int fd;
  short events;
  short revents;
};

#define POLLIN   0x001
#define POLLPRI  0x002
#define POLLOUT  0x004
#define POLLERR  0x008
#define POLLHUP  0x010
#define POLLNVAL 0x020
#define POLLRDNORM 0x040
#define POLLRDBAND 0x080
#define POLLWRNORM 0x100
#define POLLWRBAND 0x200
#define POLLMSG    0x400
#define POLLRDHUP  0x2000

int poll(struct pollfd *fds, nfds_t nfds, int timeout);

/* ppoll(2): a timespec timeout (0: none) and a signal mask held while it waits */
struct timespec;
int ppoll(struct pollfd *fds, nfds_t nfds, const struct timespec *timeout, const void *sigmask);

#endif
