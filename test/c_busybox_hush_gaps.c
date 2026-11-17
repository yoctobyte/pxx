/* Two busybox hush (NOMMU) gaps pxx2 hit building it for Gibux:
   - libbb/vfork_daemon_rexec.c BUILD_BUG_ON(CONFIG_BUSYBOX_EXEC_PATH[0] != '/'):
     a subscripted string literal is a character in a constant expression
     (bug-c-a-subscripted-string-literal-folds-to-1).
   - hush's getpgrp(), missing from crtl's <unistd.h>.
   - xtensa's tty/file ioctl numbers are not asm-generic's (hush's tcgetpgrp
     got ENOTTY on Gibux): FIONREAD and FIONBIO on a pipe, which needs no
     terminal (bug-crtl-xtensa-tty-ioctls-use-the-generic-numbers).
   Run on x86-64 and xtensa; output is gcc's. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#define EXEC_PATH "/proc/self/exe"
#define BUILD_BUG_ON(condition) ((void)sizeof(char[1 - 2*!!(condition)]))
static const int fifth = "abcdef"[4];
int main(void)
{
    BUILD_BUG_ON(EXEC_PATH[0] != '/');
    printf("%d %d %d pgrp %d\n", EXEC_PATH[0] == '/', fifth,
           (int)sizeof(char["ab" "cd"[3]]), getpgrp() == getpgid(0));
    {
        int fds[2], n = -1, on = 1, r;
        char buf[8];
        if (pipe(fds) != 0) return 1;
        if (write(fds[1], "hello", 5) != 5) return 1;
        r = ioctl(fds[0], FIONREAD, &n);
        printf("fionread %d %d\n", r, n);
        if (read(fds[0], buf, 5) != 5) return 1;
        r = ioctl(fds[0], FIONBIO, &on);
        n = r == 0 ? (int)read(fds[0], buf, 1) : -2;   /* a failed FIONBIO would block */
        printf("fionbio %d read %d eagain %d\n", r, n, errno == EAGAIN);
    }
    return 0;
}
