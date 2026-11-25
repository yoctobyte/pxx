/* SPDX-License-Identifier: Zlib */
/* C runtime: epoll (see <sys/epoll.h>). The newer ABIs (aarch64, riscv) have
   only epoll_create1 and epoll_pwait, so epoll_create and epoll_wait use those
   where the older calls are missing. The signal mask goes to the kernel as
   its 8-byte set, as sigprocmask passes it. */
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

int epoll_create1(int flags)
{
#ifdef SYS_epoll_create1
  return (int)syscall(SYS_epoll_create1, (long)flags);
#else
  (void)flags;
  errno = ENOSYS;
  return -1;
#endif
}

int epoll_create(int size)
{
  if (size <= 0) { errno = EINVAL; return -1; }
#ifdef SYS_epoll_create
  return (int)syscall(SYS_epoll_create, (long)size);
#else
  return epoll_create1(0);
#endif
}

int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event)
{
#ifdef SYS_epoll_ctl
  return (int)syscall(SYS_epoll_ctl, (long)epfd, (long)op, (long)fd, (long)event);
#else
  (void)epfd; (void)op; (void)fd; (void)event;
  errno = ENOSYS;
  return -1;
#endif
}

int epoll_pwait(int epfd, struct epoll_event *events, int maxevents, int timeout,
                const sigset_t *sigmask)
{
#ifdef SYS_epoll_pwait
  return (int)syscall(SYS_epoll_pwait, (long)epfd, (long)events, (long)maxevents,
                      (long)timeout,
                      (long)(sigmask ? (const void *)&sigmask->__val[0] : 0), 8L);
#else
  (void)epfd; (void)events; (void)maxevents; (void)timeout; (void)sigmask;
  errno = ENOSYS;
  return -1;
#endif
}

int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout)
{
#ifdef SYS_epoll_wait
  return (int)syscall(SYS_epoll_wait, (long)epfd, (long)events, (long)maxevents,
                      (long)timeout);
#else
  return epoll_pwait(epfd, events, maxevents, timeout, 0);
#endif
}
