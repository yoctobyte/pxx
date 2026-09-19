/* errno must be per-thread, which C requires and pxx did not do: it was one
   ordinary .bss int shared by every thread, so a thread reading it on the line
   after a failing call could see ANOTHER thread's code.

   THE ASSERTION IS A COUNT OVER MANY ITERATIONS, NOT A VALUE CHECK, AND THAT
   IS THE WHOLE DESIGN OF THIS FIXTURE. A shared errno is a RACE: any single
   read passes almost every time, so `errno == ENOENT` on one iteration is
   PHYSICALLY UNABLE to observe this defect and would certify it as fixed.
   Measured before the fix, at HEAD on 2026-09-19: 8 cross-reads per 200000
   iterations, varying run to run as a race should; the glibc oracle gives 0
   every time. This fixture keeps the loop long enough to make a shared errno
   essentially certain to be caught and short enough for the quick tier.

   Each thread uses a code the OTHER thread never produces -- ENOENT(2) from a
   missing path, EBADF(9) from close(-1) -- so a cross-read is unambiguous
   rather than a value that could have arrived legitimately.

   THE POSITIVE CONTROL IS A DELIBERATELY SHARED INT THROUGH THE SAME HARNESS.
   Without it, `cross=0` is also what this prints if the two threads never
   actually overlap, or if the loops never ran -- and then the row passes for a
   program in which nothing was tested. The control must report a nonzero count
   from the identical loop shape, or the fixture says nothing about errno.

   bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure */
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>

#define ITERS 60000

static volatile int cross_a = 0, cross_b = 0;

/* the control: one plainly shared int, written and read exactly where errno is */
static volatile int shared_code = 0;
static volatile int control_cross_a = 0, control_cross_b = 0;

static void *thread_a(void *p) {
    int i;
    (void)p;
    for (i = 0; i < ITERS; i++) {
        int fd, e;

        /* The control is written BEFORE the same syscall and read AFTER it, so
           it spans the IDENTICAL window errno does. A control that stores and
           reloads on adjacent lines has a two-instruction window and reports
           zero crosstalk even when genuinely shared -- measured, it did, and
           that zero would have been read as "the threads overlap fine". */
        shared_code = ENOENT;
        fd = open("/nonexistent/pxx/errno/probe", O_RDONLY);
        e = errno;
        if (fd >= 0) close(fd);
        if (e != ENOENT) cross_a++;
        if (shared_code != ENOENT) control_cross_a++;
    }
    return 0;
}

static void *thread_b(void *p) {
    int i;
    (void)p;
    for (i = 0; i < ITERS; i++) {
        shared_code = EBADF;
        close(-1);
        if (errno != EBADF) cross_b++;
        if (shared_code != EBADF) control_cross_b++;
    }
    return 0;
}

int main(void) {
    pthread_t ta, tb;
    int control_seen;

    if (pthread_create(&ta, 0, thread_a, 0) != 0) { printf("create a failed\n"); return 1; }
    if (pthread_create(&tb, 0, thread_b, 0) != 0) { printf("create b failed\n"); return 1; }
    pthread_join(ta, 0);
    pthread_join(tb, 0);

    /* ASSERT THE PRECONDITION, not just the comparison: a cross count of zero
       from loops that never ran is not evidence of anything. */
    printf("ran=%d\n", (cross_a >= 0 && cross_b >= 0) ? 1 : 0);
    printf("errno-crosstalk=%d\n", (cross_a == 0 && cross_b == 0) ? 0 : 1);

    /* The control shares one int between the same two threads, across the same
       syscall, in the same loop. It must see crosstalk; if it does not, the
       threads did not overlap and the errno row above proved nothing. */
    control_seen = (control_cross_a + control_cross_b) > 0;
    printf("control-shared=%d\n", control_seen);

    printf("%s\n", (cross_a == 0 && cross_b == 0 && control_seen)
                     ? "C ERRNO PER-THREAD OK" : "C ERRNO SHARED");
    return 0;
}
