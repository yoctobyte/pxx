/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/epoll.h> -- epoll(7). Xorg's os/ospoll.c waits on its
 * clients and input devices with it. The constants are the kernel's
 * (uapi linux/eventpoll.h); EPOLL_CLOEXEC is O_CLOEXEC, as Linux defines it.
 *
 * struct epoll_event is PACKED ON X86-64 ONLY (12 bytes: the 64-bit data
 * right after the 32-bit events), because the kernel's is, for 32-bit
 * compatibility. Everywhere else it has natural alignment: 12 bytes on i386
 * (uint64_t is 4-aligned there), 16 on aarch64, arm32 and riscv.
 */
#ifndef PXX_CRTL_SYS_EPOLL_H
#define PXX_CRTL_SYS_EPOLL_H 1

#include <stdint.h>
#include <fcntl.h>
#include <signal.h>

#define EPOLL_CLOEXEC O_CLOEXEC

#define EPOLL_CTL_ADD 1
#define EPOLL_CTL_DEL 2
#define EPOLL_CTL_MOD 3

#define EPOLLIN        0x001
#define EPOLLPRI       0x002
#define EPOLLOUT       0x004
#define EPOLLERR       0x008
#define EPOLLHUP       0x010
#define EPOLLNVAL      0x020
#define EPOLLRDNORM    0x040
#define EPOLLRDBAND    0x080
#define EPOLLWRNORM    0x100
#define EPOLLWRBAND    0x200
#define EPOLLMSG       0x400
#define EPOLLRDHUP     0x2000
#define EPOLLEXCLUSIVE (1U << 28)
#define EPOLLWAKEUP    (1U << 29)
#define EPOLLONESHOT   (1U << 30)
#define EPOLLET        (1U << 31)

typedef union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;

struct epoll_event {
  uint32_t events;
  epoll_data_t data;
}
#if defined(__x86_64__)
__attribute__((packed))
#endif
;

int epoll_create(int size);
int epoll_create1(int flags);
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);
int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout);
int epoll_pwait(int epfd, struct epoll_event *events, int maxevents, int timeout,
                const sigset_t *sigmask);

#endif
