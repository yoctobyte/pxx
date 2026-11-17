/* crtl on xtensa issues the time64 syscalls (PAL_TIME64; Nilix implements
   those, with 64-bit __kernel_timespec): clock_gettime64 403,
   clock_nanosleep_time64 407, ppoll_time64 414, pselect6_time64 413,
   utimensat_time64 412. tools/check_xtensa_time64_syscalls.py runs this under
   qemu-xtensa -strace and refuses any time32 number (245 195 273 272 296).
   feature-xtensa-crtl-uses-the-time64-syscalls */
#include <stdio.h>
#include <time.h>
#include <poll.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
int main(void)
{
    struct timespec a, b, d = { 0, 2000000 };
    struct timeval tv = { 0, 1000 };
    int ok = 0;
    clock_gettime(CLOCK_REALTIME, &a);
    nanosleep(&d, 0);
    poll(0, 0, 1);
    select(0, 0, 0, 0, &tv);
    clock_gettime(CLOCK_REALTIME, &b);
    if (b.tv_sec > 1700000000 && (b.tv_sec > a.tv_sec || b.tv_nsec >= a.tv_nsec + 2000000)) ok = 1;
    printf("time64 %s\n", ok ? "ok" : "BAD");
    return 0;
}
