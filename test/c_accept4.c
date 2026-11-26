#define _GNU_SOURCE   /* accept4, for gcc */
/* accept4 (curl's cf-socket.c): the accepted socket carries the flags asked
   for, flags 0 is plain accept, an unknown flag is EINVAL. Loopback TCP.
   feature-crtl-the-libc-gaps-curl-found */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static int listener(struct sockaddr_in *sa) {
  socklen_t len = sizeof *sa;
  int s = socket(AF_INET, SOCK_STREAM, 0);
  memset(sa, 0, sizeof *sa);
  sa->sin_family = AF_INET;
  sa->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  sa->sin_port = 0;
  if (bind(s, (struct sockaddr *)sa, sizeof *sa) < 0 || listen(s, 4) < 0) return -1;
  getsockname(s, (struct sockaddr *)sa, &len);
  return s;
}

static int one(int flags) {
  struct sockaddr_in sa, peer;
  socklen_t plen = sizeof peer;
  int s = listener(&sa), c, a, r;
  if (s < 0) return printf("listen failed\n"), 1;
  c = socket(AF_INET, SOCK_STREAM, 0);
  if (connect(c, (struct sockaddr *)&sa, sizeof sa) < 0) return printf("connect failed\n"), 1;
  a = accept4(s, (struct sockaddr *)&peer, &plen, flags);
  if (a < 0) { printf("flags %#x: errno %s\n", flags, errno == EINVAL ? "EINVAL" : "other"); r = 0; }
  else {
    printf("flags %#x: cloexec %d nonblock %d family %d loopback %d\n", flags,
           (fcntl(a, F_GETFD) & FD_CLOEXEC) != 0, (fcntl(a, F_GETFL) & O_NONBLOCK) != 0,
           peer.sin_family, peer.sin_addr.s_addr == htonl(INADDR_LOOPBACK));
    close(a); r = 0;
  }
  close(c); close(s);
  return r;
}

int main(void) {
  return one(0) | one(SOCK_CLOEXEC) | one(SOCK_NONBLOCK) |
         one(SOCK_CLOEXEC | SOCK_NONBLOCK) | one(0x40000000);
}
