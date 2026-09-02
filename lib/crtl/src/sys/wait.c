/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sys/wait — the reaping calls, beside their own header.
 *
 * They live HERE and not in unistd.c even though they are one line each, and
 * the reason is a real failure mode rather than tidiness: crtl auto-pulls a
 * header's SIBLING .c, so a program that includes only <sys/wait.h> would have
 * got the declaration and no definition, then silently imported glibc's
 * waitpid — which really does wait, on a process that was never forked. A
 * definition in the wrong file is worse than a missing one, because the link
 * succeeds. tools/crtl_reachability.py is the guard that catches it.
 */

#include <sys/wait.h>
#include <errno.h>

/* WIRED, and this comment used to say it was "a bridge away from being real
   rather than a missing syscall ... worth wiring the moment there is something
   to wait for". That moment is fork() becoming real in unistd.c; the two move
   together and neither is useful alone. A fork() without a waitpid() is worse
   than neither, because the caller then spawns children it cannot reap and
   accumulates zombies rather than failing.

   ECHILD still reaches callers who have no children — but it now comes from
   the KERNEL rather than from crtl asserting it, which is the whole difference:
   the old stub returned ECHILD to a caller that DID have a child, and that is
   indistinguishable from the child already being reaped. */

extern int __pxx_wait4(int pid, void *wstatus, int options, void *rusage);

int waitpid(int pid, int *status, int options)
{
  int rc = __pxx_wait4(pid, status, options, 0);
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

/* wait() is waitpid(-1, status, 0) — POSIX defines it that way, so it is
   expressed that way rather than given a second path to the same syscall. */
int wait(int *status)
{
  return waitpid(-1, status, 0);
}

/* wait4(2) is the PAL entry itself; waitpid above is this call with a NULL
   rusage. It is spelled out rather than made the primitive because waitpid is
   the one every program uses and a wrapper-of-a-wrapper buys nothing. */
int wait4(int pid, int *status, int options, void *rusage)
{
  int rc = __pxx_wait4(pid, status, options, rusage);
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

/* wait3(2): BSD's older spelling of "reap any child, with usage". */
int wait3(int *status, int options, void *rusage)
{
  return wait4(-1, status, options, rusage);
}

