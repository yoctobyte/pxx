/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: adjtimex(2).
 *
 * A SUCCESSFUL adjtimex RETURNS A CLOCK STATE, NOT ZERO. TIME_INS, TIME_DEL
 * and the rest are 1..5 and are SUCCESS -- only -1 is an error. Code written
 * as `if (adjtimex(&t))' therefore reports a failure every time a leap second
 * is pending, which is precisely when the caller is watching. syscall() only
 * turns a NEGATIVE return into -1/errno, so the state passes through.
 *
 * ntp_adjtime is the same call under its NTP name; ntp_gettime is the
 * read-only half, expressed as an adjtimex with no modes rather than as a
 * separate syscall, which is what glibc does too.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 */
#include <sys/timex.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>

int adjtimex(struct timex *ntx)
{
#ifdef SYS_adjtimex
  return (int)syscall(SYS_adjtimex, (long)ntx);
#else
  (void)ntx;
  errno = ENOSYS;
  return -1;
#endif
}

int ntp_adjtime(struct timex *tntx)
{
  return adjtimex(tntx);
}

int ntp_gettime(struct ntptimeval *ntv)
{
  struct timex tntx;
  int rc;

  memset(&tntx, 0, sizeof tntx);
  tntx.modes = 0;               /* read-only: change nothing */
  rc = adjtimex(&tntx);
  if (rc < 0)
    return rc;
  ntv->time = tntx.time;
  ntv->maxerror = tntx.maxerror;
  ntv->esterror = tntx.esterror;
  ntv->tai = tntx.tai;
  return rc;
}
