/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sched.h>'s bodies.
 *
 * EVERY ENTRY IS #ifdef'd ON ITS SYSCALL NUMBER, not on the architecture. An
 * `#if defined(__x86_64__)' chain is the shape that compiled a call to syscall
 * ZERO on arm32 once (SYS_statfs was undeclared, so the expression became 0
 * with a warning and the program read a file it never opened). A number that
 * does not exist for this target must make the FUNCTION refuse, loudly and at
 * runtime, rather than make the call land somewhere.
 *
 * sched_getaffinity/sched_setaffinity return 0, not the kernel's byte count --
 * see the header. syscall() in src/unistd.c has already translated -errno into
 * -1 plus errno, so nothing here touches errno on the error path.
 */
#include <sched.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

void CPU_ZERO_S(size_t setsize, cpu_set_t *setp)
{
  size_t i;
  unsigned char *p = (unsigned char *)setp;
  for (i = 0; i < setsize; i++) p[i] = 0;
}

int CPU_COUNT_S(size_t setsize, const cpu_set_t *setp)
{
  size_t i;
  int n = 0;
  const unsigned char *p = (const unsigned char *)setp;
  for (i = 0; i < setsize; i++) {
    unsigned int b = p[i];
    while (b) { n += (int)(b & 1u); b >>= 1; }
  }
  return n;
}

int sched_yield(void)
{
#ifdef SYS_sched_yield
  return (int)syscall(SYS_sched_yield);
#else
  errno = ENOSYS;
  return -1;
#endif
}

int sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t *mask)
{
#ifdef SYS_sched_getaffinity
  long rc = syscall(SYS_sched_getaffinity, (long)pid, (long)cpusetsize, (long)mask);
  if (rc < 0) return -1;
  /* The kernel answers with the bytes written; glibc answers 0. Callers are
     written against glibc, and `== 0' is how busybox tests it. */
  return 0;
#else
  (void)pid; (void)cpusetsize; (void)mask;
  errno = ENOSYS;
  return -1;
#endif
}

int sched_setaffinity(pid_t pid, size_t cpusetsize, const cpu_set_t *mask)
{
#ifdef SYS_sched_setaffinity
  long rc = syscall(SYS_sched_setaffinity, (long)pid, (long)cpusetsize, (long)mask);
  if (rc < 0) return -1;
  return 0;
#else
  (void)pid; (void)cpusetsize; (void)mask;
  errno = ENOSYS;
  return -1;
#endif
}

int sched_get_priority_max(int policy)
{
#ifdef SYS_sched_get_priority_max
  return (int)syscall(SYS_sched_get_priority_max, (long)policy);
#else
  (void)policy;
  errno = ENOSYS;
  return -1;
#endif
}

int sched_get_priority_min(int policy)
{
#ifdef SYS_sched_get_priority_min
  return (int)syscall(SYS_sched_get_priority_min, (long)policy);
#else
  (void)policy;
  errno = ENOSYS;
  return -1;
#endif
}

int unshare(int flags)
{
#ifdef SYS_unshare
  return (int)syscall(SYS_unshare, (long)flags);
#else
  (void)flags;
  errno = ENOSYS;
  return -1;
#endif
}

int setns(int fd, int nstype)
{
#ifdef SYS_setns
  return (int)syscall(SYS_setns, (long)fd, (long)nstype);
#else
  (void)fd; (void)nstype;
  errno = ENOSYS;
  return -1;
#endif
}

/* The policy trio. Every one is #ifdef'd on its own number, per this file's
 * header rule -- arm32 and xtensa have no syscall table here and must refuse
 * at runtime rather than call number zero.
 *
 * sched_getscheduler RETURNS THE POLICY, and a policy of 0 is SCHED_OTHER --
 * a real answer, not a failure. Only -1 is an error, so `if
 * (!sched_getscheduler(pid))' is a test for SCHED_OTHER and not for success.
 * The SCHED_RESET_ON_FORK bit is left in place; see the header.
 */
int sched_getscheduler(pid_t pid)
{
#ifdef SYS_sched_getscheduler
  return (int)syscall(SYS_sched_getscheduler, (long)pid);
#else
  (void)pid;
  errno = ENOSYS;
  return -1;
#endif
}

int sched_setscheduler(pid_t pid, int policy, const struct sched_param *param)
{
#ifdef SYS_sched_setscheduler
  return (int)syscall(SYS_sched_setscheduler, (long)pid, (long)policy,
                      (long)param);
#else
  (void)pid; (void)policy; (void)param;
  errno = ENOSYS;
  return -1;
#endif
}

int sched_getparam(pid_t pid, struct sched_param *param)
{
#ifdef SYS_sched_getparam
  return (int)syscall(SYS_sched_getparam, (long)pid, (long)param);
#else
  (void)pid; (void)param;
  errno = ENOSYS;
  return -1;
#endif
}
