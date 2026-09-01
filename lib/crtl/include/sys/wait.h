/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_WAIT_H
#define PXX_CRTL_SYS_WAIT_H 1

/* Process reaping. The MACROS here are real and exact — they only decode an
   int the kernel already produced, so they are correct wherever the status
   came from.

   THE CALLS ARE NOW REAL TOO. This comment used to say "the PAL exposes no
   wait4/waitid", which was the third place in crtl to state a version of that
   claim and, like the other two, it was false when written: PalWait4 existed
   and subprocess.pas was already calling it. The stubs were downstream of
   fork() being stubbed, and fork() was stubbed because a PAL entry that issued
   SYS_fork was NAMED PalVfork. One misleading name, three comments that agreed
   with each other, and busybox ash failing on `can't fork'. */

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

/* Both are wait4(2) underneath. ECHILD still reaches the caller when there is
   genuinely nothing to reap — it is now the KERNEL saying so rather than crtl
   asserting it, which is the difference that matters. */
int wait(int *status);
int waitpid(int pid, int *status, int options);

#endif
