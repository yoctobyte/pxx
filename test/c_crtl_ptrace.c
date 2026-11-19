/* crtl's <sys/ptrace.h> and ptrace(), against gcc + glibc. <sys/types.h> is
   included FIRST on purpose: that order failed on a conflicting __pid_t while
   crtl had no <sys/ptrace.h> and the host's was reached (Rainyday,
   drivers/lib/confine_test.c). The PEEKs check glibc's convention: the word
   is RETURNED, errno 0, so a stored -1 is told from a failure by errno.
   bug-crtl-sys-ptrace-h-missing-and-pid-t-long */
#include <sys/types.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <signal.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>

static long secret = 0x12345678L;
static long minus = -1;

int main(void)
{
    int st;
    long w;
    pid_t child = fork();
    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, 0, 0) != 0) _exit(3);
        raise(SIGSTOP);
        _exit(7);
    }
    waitpid(child, &st, 0);
    printf("stopped %d sig %d\n", WIFSTOPPED(st), WSTOPSIG(st));
    errno = 0;
    w = ptrace(PTRACE_PEEKDATA, child, &secret, 0);
    printf("peek %lx errno %d\n", w, errno);
    errno = 0;
    w = ptrace(PTRACE_PEEKDATA, child, &minus, 0);
    printf("peek-1 %ld errno %d\n", w, errno);
    errno = 0;
    w = ptrace(PTRACE_PEEKDATA, child, (void *)8, 0);
    printf("badpeek %ld errno-set %d\n", w, errno != 0);
    printf("poke %ld\n", ptrace(PTRACE_POKEDATA, child, &secret, (void *)42L));
    printf("repeek %ld\n", ptrace(PTRACE_PEEKDATA, child, &secret, 0));
    printf("cont %ld\n", ptrace(PTRACE_CONT, child, 0, 0));
    waitpid(child, &st, 0);
    printf("exit %d code %d\n", WIFEXITED(st), WEXITSTATUS(st));
    errno = 0;
    w = ptrace(PTRACE_ATTACH, getpid(), 0, 0);
    printf("selfattach %ld errno-set %d\n", w, errno != 0);
    return 0;
}
