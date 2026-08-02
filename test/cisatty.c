/* isatty (feature-crtl-libc-gap-batch-2026-08, finishing round 1's last gap).
 *
 * It was left out earlier for two reasons, and BOTH turned out to be wrong:
 *   "crtl has no ioctl bridge"  — PalIoctl exists; only the __pxx_ wrapper was
 *                                 missing, which is a one-liner.
 *   "the true-positive case is unverifiable without a controlling terminal"
 *                               — /dev/ptmx IS a tty and can be opened from a
 *                                 non-interactive build, so both directions are
 *                                 testable after all.
 *
 * The implementation is the TCGETS ioctl, not fstat + S_ISCHR: /dev/null is a
 * character device and is NOT a tty, so the fstat version answers 1 for
 * redirected output and every "am I interactive" branch takes the wrong path.
 * That is exactly why this test checks /dev/null and a directory as well as a
 * real terminal — a one-sided test would pass against the wrong implementation.
 */
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
int main(void) {
  int p = open("/dev/ptmx", O_RDWR);
  int n = open("/dev/null", O_RDWR);
  int f = open("/tmp", O_RDONLY);
  printf("ptmx_is_tty=%d null_is_tty=%d dir_is_tty=%d bad_fd=%d\n",
         p >= 0 ? isatty(p) : -1, n >= 0 ? isatty(n) : -1,
         f >= 0 ? isatty(f) : -1, isatty(999));
  return 0;
}
