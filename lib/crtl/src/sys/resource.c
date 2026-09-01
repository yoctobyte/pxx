/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: getrlimit / setrlimit, both on prlimit64.
 *
 * Needed by busybox's `ulimit' (shell/shell_common.c:616). Found attempting
 * rung 2 (feature-c-corpus-busybox-multi-applet).
 *
 * THE STRUCT IS NOT THE KERNEL'S, AND THAT IS THE WHOLE CARE HERE.
 * prlimit64 reads and writes `struct rlimit64', two __u64. crtl's `struct
 * rlimit' is two rlim_t, and rlim_t is `unsigned long' -- 64 bits on x86-64 and
 * aarch64, THIRTY-TWO on i386, arm32, riscv32 and xtensa. Handing the kernel a
 * pointer to the user's struct would therefore work perfectly on the two
 * targets anyone tests on and let the kernel write SIXTEEN bytes into an EIGHT
 * byte object everywhere else. So the call always goes through a local 64-bit
 * pair and the values are converted, on every target, rather than aliased on
 * the ones where it would happen to be safe.
 *
 * Narrowing saturates to RLIM_INFINITY rather than truncating: a 32-bit caller
 * asking about a limit above 4GB is told "unlimited", which is the direction
 * that cannot make it exceed a real limit. Truncating would report a small
 * number for a huge limit and a program would obey a restriction that is not
 * there -- and RLIM_INFINITY is itself all-ones, so it round-trips unchanged.
 */
#include <sys/resource.h>
#include <errno.h>

extern int __pxx_prlimit(int resource, void *newLim, void *oldLim);

struct __pxx_rlimit64 {
  unsigned long long rlim_cur;
  unsigned long long rlim_max;
};

/* The kernel's "no limit" is all-ones at 64 bits, whatever rlim_t is here. */
#define PXX_RLIM64_INFINITY (~0ULL)

static rlim_t narrow(unsigned long long v) {
  if (v >= (unsigned long long)RLIM_INFINITY) return RLIM_INFINITY;
  return (rlim_t)v;
}

static unsigned long long widen(rlim_t v) {
  if (v == RLIM_INFINITY) return PXX_RLIM64_INFINITY;
  return (unsigned long long)v;
}

int getrlimit(int resource, struct rlimit *rlim) {
  struct __pxx_rlimit64 out;
  int rc;
  if (!rlim) { errno = EFAULT; return -1; }
  out.rlim_cur = 0;
  out.rlim_max = 0;
  rc = __pxx_prlimit(resource, 0, &out);
  if (rc < 0) { errno = -rc; return -1; }
  rlim->rlim_cur = narrow(out.rlim_cur);
  rlim->rlim_max = narrow(out.rlim_max);
  return 0;
}

int setrlimit(int resource, const struct rlimit *rlim) {
  struct __pxx_rlimit64 in;
  int rc;
  if (!rlim) { errno = EFAULT; return -1; }
  in.rlim_cur = widen(rlim->rlim_cur);
  in.rlim_max = widen(rlim->rlim_max);
  rc = __pxx_prlimit(resource, &in, 0);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* ---- process scheduling priority ------------------------------------------
 *
 * THE KERNEL DOES NOT RETURN THE NICE VALUE. getpriority(2) would have to
 * return -20..19, and a syscall cannot distinguish a nice of -1 from -EPERM,
 * so the kernel returns 20-nice (1..40) instead and every libc converts on the
 * way out. The PAL passes that biased number through unchanged precisely so
 * that a negative result still means -errno on the way in; the single
 * conversion lives here, next to errno.
 *
 * -1 IS A VALID RETURN: a process running at nice -1 is reported as -1, the
 * same value a failure would produce. So the caller cannot use the return
 * value to detect failure, which is why POSIX has it set errno to 0 beforehand
 * and read errno afterwards -- and why nothing below writes errno on success.
 *
 * Needed by busybox coreutils/nice.c and util-linux/renice.c.
 */
extern int __pxx_getpriority(int which, int who);
extern int __pxx_setpriority(int which, int who, int prio);

int getpriority(int which, id_t who) {
  int rc = __pxx_getpriority(which, (int)who);
  if (rc < 0) { errno = -rc; return -1; }
  return 20 - rc;
}

int setpriority(int which, id_t who, int prio) {
  int rc = __pxx_setpriority(which, (int)who, prio);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}
