/* crtl bodies guarded on a SYS_ number: do they REACH THE KERNEL on this
 * target, or take their `#else errno = ENOSYS' arm?
 *
 * This existed as a throwaway probe first and it found that every one of them
 * was inert on arm32 -- 56 guards across 19 files -- because
 * <sys/syscall.h> had no __arm__ arm at all
 * (bug-b-every-crtl-body-guarded-on-a-syscall-number-is-inert-on-arm32).
 *
 * IT PRINTS errno AND NOT rc, WHICH IS THE ONLY REASON IT CAN SEE ANYTHING.
 * rc is -1 for "the kernel refused" and -1 for "there is no number", so a
 * whole subsystem being absent on one target looks exactly like ten calls
 * that happened to fail.
 *
 * NO EXPECTED CONSTANTS. The Makefile compares one target's output against
 * ANOTHER target's, so the assertion is agreement between two independent
 * builds and there is no per-target literal to go stale. Each row's arguments
 * are chosen so the right answer is DISTINCTIVE -- 0, EPERM, EBADF, EINVAL --
 * because a row whose expected value is also its failure value cannot fail.
 *
 * readv's arguments are load-bearing: `readv(-1, NULL, 0)' answers 0 on some
 * kernels and EBADF on others, because with iovcnt 0 the fd need never be
 * looked at. That ambiguity read as a wrong syscall number for an hour. With a
 * real iovec and iovcnt 1, EBADF is the only correct answer anywhere.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <sched.h>
#include <sys/mman.h>
#include <sys/statfs.h>
#include <sys/file.h>
#include <sys/uio.h>
#include <sys/prctl.h>

#define ROW(name, call) do { errno = 0; (void)(call); \
    printf("%-20s errno=%d\n", name, errno); } while (0)

int main(void) {
  struct sched_param sp;
  struct statfs sb;
  struct iovec iov;
  char buf[8];
  iov.iov_base = buf; iov.iov_len = sizeof buf;

  ROW("sched_getscheduler", sched_getscheduler(0));
  ROW("sched_getparam",     sched_getparam(0, &sp));
  ROW("sched_yield",        sched_yield());
  ROW("mlock",              mlock((void *)0, 0));
  ROW("munlock",            munlock((void *)0, 0));
  ROW("acct",               acct("/nonexistent-pxx"));
  ROW("statfs",             statfs("/", &sb));
  ROW("flock",              flock(-1, 1));
  ROW("prctl",              prctl(0, 0, 0, 0, 0));
  ROW("readv",              readv(-1, &iov, 1));
  return 0;
}
