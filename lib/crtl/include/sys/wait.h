/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_WAIT_H
#define PXX_CRTL_SYS_WAIT_H 1

/* Process reaping. The MACROS here are real and exact — they only decode an
   int the kernel already produced, so they are correct wherever the status
   came from. The CALLS are ENOSYS stubs: the PAL exposes no wait4/waitid, and
   with fork() also unavailable there is nothing to reap.

   Kept as a pair on purpose: real code writes `if (waitpid(...) > 0 &&
   WIFEXITED(st))`, and it must be able to COMPILE that against us even where
   it will never take the branch. See the note beside the other ENOSYS stubs
   in lib/crtl/src/unistd.c. */

#include <sys/types.h>

#define WNOHANG   1
#define WUNTRACED 2
#define WCONTINUED 8

#define WEXITSTATUS(s)  (((s) & 0xff00) >> 8)
#define WTERMSIG(s)     ((s) & 0x7f)
#define WSTOPSIG(s)     WEXITSTATUS(s)
#define WIFEXITED(s)    (WTERMSIG(s) == 0)
#define WIFSIGNALED(s)  ((((s) & 0x7f) + 1) >> 1 > 0)
#define WIFSTOPPED(s)   (((s) & 0xff) == 0x7f)
#define WIFCONTINUED(s) ((s) == 0xffff)
#define WCOREDUMP(s)    ((s) & 0x80)

/* Both fail with -1/ECHILD: there are no children, because fork() is itself
   an ENOSYS stub. ECHILD rather than ENOSYS is deliberate — it is the answer
   POSIX defines for "nothing to wait for", so a caller's existing error path
   handles it correctly instead of meeting a code it has never seen. */
int wait(int *status);
int waitpid(int pid, int *status, int options);

#endif
