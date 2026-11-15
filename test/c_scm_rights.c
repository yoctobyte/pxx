/* Descriptor passing: socketpair, sendmsg/recvmsg with an SCM_RIGHTS control
   message, MSG_CMSG_CLOEXEC, MSG_CTRUNC, and recv with MSG_PEEK/MSG_DONTWAIT.
   Gibux's USB disk keeper hands each disk's socket to a root helper this way.
   feature-crtl-descriptor-passing-socket-api */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>

static int send_fd(int s, int fd) {
  char byte = 'F';
  struct iovec iov = { &byte, 1 };
  char ctl[CMSG_SPACE(sizeof(int))];
  struct msghdr m;
  struct cmsghdr *c;
  memset(&m, 0, sizeof m);
  memset(ctl, 0, sizeof ctl);
  m.msg_iov = &iov; m.msg_iovlen = 1;
  m.msg_control = ctl; m.msg_controllen = sizeof ctl;
  c = CMSG_FIRSTHDR(&m);
  c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS;
  c->cmsg_len = CMSG_LEN(sizeof(int));
  memcpy(CMSG_DATA(c), &fd, sizeof(int));
  return (int)sendmsg(s, &m, 0);
}

int main(void) {
  int sv[2], dg[2], p[2], got = -1, n;
  char byte = 0, buf[8];
  struct iovec iov = { &byte, 1 };
  char ctl[CMSG_SPACE(sizeof(int))];
  struct msghdr m;
  struct cmsghdr *c;

  printf("sizes %zu %zu %zu %zu\n", sizeof(struct msghdr), sizeof(struct cmsghdr),
         (size_t)CMSG_LEN(sizeof(int)), (size_t)CMSG_SPACE(sizeof(int)));
  if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) != 0) { perror("socketpair"); return 1; }
  printf("cloexec pair %d\n", (fcntl(sv[0], F_GETFD) & FD_CLOEXEC) != 0);
  if (pipe(p) != 0) return 1;
  if (write(p[1], "pipe!", 5) != 5) return 1;

  /* nothing queued: a non-blocking peek says EAGAIN */
  n = (int)recv(sv[1], buf, sizeof buf, MSG_PEEK | MSG_DONTWAIT);
  printf("empty peek %d %d\n", n, n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK));

  printf("sent %d\n", send_fd(sv[0], p[0]));
  n = (int)recv(sv[1], buf, 1, MSG_PEEK | MSG_DONTWAIT);
  printf("peek %d %c\n", n, buf[0]);

  memset(&m, 0, sizeof m);
  m.msg_iov = &iov; m.msg_iovlen = 1;
  m.msg_control = ctl; m.msg_controllen = sizeof ctl;
  n = (int)recvmsg(sv[1], &m, MSG_CMSG_CLOEXEC);
  for (c = CMSG_FIRSTHDR(&m); c; c = CMSG_NXTHDR(&m, c))
    if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS)
      memcpy(&got, CMSG_DATA(c), sizeof(int));
  printf("recv %d %c fd %d ctrunc %d\n", n, byte, got >= 0, (m.msg_flags & MSG_CTRUNC) != 0);
  if (got < 0) return 1;
  printf("cloexec got %d\n", (fcntl(got, F_GETFD) & FD_CLOEXEC) != 0);
  memset(buf, 0, sizeof buf);
  n = (int)read(got, buf, 5);
  printf("read %d %s\n", n, buf);

  /* a control buffer too small for the descriptor: MSG_CTRUNC */
  if (socketpair(AF_UNIX, SOCK_DGRAM, 0, dg) != 0) return 1;
  send_fd(dg[0], p[0]);
  memset(&m, 0, sizeof m);
  m.msg_iov = &iov; m.msg_iovlen = 1;
  m.msg_control = ctl; m.msg_controllen = sizeof(struct cmsghdr);
  n = (int)recvmsg(dg[1], &m, 0);
  printf("dgram %d ctrunc %d\n", n, (m.msg_flags & MSG_CTRUNC) != 0);
  return 0;
}
