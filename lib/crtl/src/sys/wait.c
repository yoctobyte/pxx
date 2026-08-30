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

/* ECHILD, not ENOSYS: with fork() unavailable (lib/crtl/src/unistd.c) there are
   no children to reap, and ECHILD is the code POSIX defines for "nothing to
   wait for" — so a caller's existing error path handles it instead of meeting a
   code it has never seen. The W* decode macros in the header ARE real; they
   only take apart an int the kernel already produced.

   The PAL DOES have PalWait4, so this is a bridge away from being real rather
   than a missing syscall, and it becomes worth wiring the moment there is
   something to wait for. Recorded because the opposite claim — "no PAL entry"
   — was written here first and was wrong. */
int wait(int *status)
{
  (void)status;
  errno = ECHILD;
  return -1;
}

int waitpid(int pid, int *status, int options)
{
  (void)pid; (void)status; (void)options;
  errno = ECHILD;
  return -1;
}
