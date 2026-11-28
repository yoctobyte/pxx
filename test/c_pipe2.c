/* SPDX-License-Identifier: Zlib */
/* pipe2: O_CLOEXEC and O_NONBLOCK land on both ends at creation, flags 0 is
   pipe(), a bad flag is EINVAL; data flows. Row c_pipe2_26, against gcc.
   feature-crtl-pipe2 */
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

int main(void)
{
    int p[2], q[2], r[2];
    char c = 0;
    if (pipe2(p, O_CLOEXEC | O_NONBLOCK) != 0) return 1;
    printf("cloexec %d %d\n", (fcntl(p[0], F_GETFD) & FD_CLOEXEC) != 0,
           (fcntl(p[1], F_GETFD) & FD_CLOEXEC) != 0);
    printf("nonblock %d %d\n", (fcntl(p[0], F_GETFL) & O_NONBLOCK) != 0,
           (fcntl(p[1], F_GETFL) & O_NONBLOCK) != 0);
    {
        long n = (long)read(p[0], &c, 1);   /* errno read AFTER the call: argument order is unspecified */
        printf("empty read %ld eagain %d\n", n, errno == EAGAIN);
    }
    if (write(p[1], "x", 1) != 1 || read(p[0], &c, 1) != 1) return 2;
    printf("data %c\n", c);
    if (pipe2(q, 0) != 0) return 3;
    printf("plain %d %d\n", (fcntl(q[0], F_GETFD) & FD_CLOEXEC) != 0,
           (fcntl(q[0], F_GETFL) & O_NONBLOCK) != 0);
    errno = 0;
    {
        int rc = pipe2(r, 0x7fffffff);
        printf("bad %d einval %d\n", rc, errno == EINVAL);
    }
    return 0;
}
