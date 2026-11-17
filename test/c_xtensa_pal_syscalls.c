/* The PAL calls hosted xtensa used to refuse without a syscall (uname(2)
   returned -1 and BusyBox `uname -a` printed garbage on Nilix). Each one runs;
   tools/check_xtensa_pal_syscalls.py compares the output with x86-64 and reads
   qemu-xtensa -strace for the syscall names.
   bug-xtensa-pal-refused-nineteen-syscalls-it-had-numbers-for */
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/utsname.h>
#include <sys/times.h>
#include <sys/resource.h>
#include <sys/stat.h>

int main(void)
{
    struct utsname u;
    struct tms t;
    struct rlimit rl;
    struct rusage ru;
    sigset_t set, old;
    gid_t groups[64];
    int fd, ok;
    memset(&u, 0, sizeof u);
    ok = uname(&u);   /* each call SEQUENCED before its result is read: printf's
                         argument order is unspecified (gcc x86-64 goes right to left) */
    printf("uname %d sysname %s nodename-set %d\n", ok, u.sysname, u.nodename[0] != 0);
    printf("times %d\n", times(&t) != (clock_t)-1);
    ok = getrlimit(RLIMIT_NOFILE, &rl);
    printf("getrlimit %d cur>0 %d\n", ok, rl.rlim_cur > 0);
    printf("getrusage %d\n", getrusage(RUSAGE_SELF, &ru));
    printf("getpgid %d getsid %d\n", getpgid(0) > 0, getsid(0) > 0);
    printf("setpgid %d\n", setpgid(0, 0));
    printf("getpriority-ok %d\n", getpriority(PRIO_PROCESS, 0) >= -20);
    ok = getpriority(PRIO_PROCESS, 0);
    printf("setpriority %d\n", setpriority(PRIO_PROCESS, 0, ok));
    printf("getgroups %d\n", getgroups(64, groups) >= 0);
    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    ok = sigprocmask(SIG_BLOCK, &set, &old);
    fd = sigprocmask(SIG_BLOCK, NULL, &old) == 0 && sigismember(&old, SIGUSR1);
    printf("sigprocmask %d blocked %d\n", ok, fd);
    ok = (int)alarm(100);
    fd = alarm(0) > 0;
    printf("alarm %d then %d\n", ok, fd);
    fd = open("/proc/self/stat", O_RDONLY);
    printf("fdatasync-ran %d\n", fdatasync(fd) <= 0);
    close(fd);
    sync();
    printf("umask %o\n", (unsigned)umask(022) & 0);
    return 0;
}
