/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_WAIT_H
#define PXX_CRTL_SYS_WAIT_H 1

/* Process reaping.

   THIS COMMENT USED TO SAY "the MACROS here are real and exact -- they only
   decode an int the kernel already produced, so they are correct wherever the
   status came from", AND IT WAS THE THING THAT WAS WRONG.
   WIFSIGNALED was transcribed without the `(signed char)' cast, which is the
   whole of glibc's definition and looks like noise. For a STOPPED child the
   low 7 bits are 0x7f, so ((s & 0x7f) + 1) is 0x80: as a signed char that is
   -128, >>1 is -64, and the macro is false. Without the cast the same
   expression is 64, and WIFSIGNALED answered TRUE -- with WTERMSIG 127 -- for
   every stopped or continued child, on ALL FIVE targets, for as long as the
   header has existed. "Only decodes an int" was true and the decode was
   wrong; a macro reading a kernel value is not thereby correct.
   NOTHING FOUND IT because nothing in the tree stopped a child. Every caller
   forked, exited, and read WIFEXITED -- the arm where the cast cannot matter.
   test/c_crtl_wait.c stops one, which is why it is there.

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
#define WIFSIGNALED(s)  (((signed char) (((s) & 0x7f) + 1) >> 1) > 0)
#define WIFSTOPPED(s)   (((s) & 0xff) == 0x7f)
#define WIFCONTINUED(s) ((s) == 0xffff)
#define WCOREDUMP(s)    ((s) & 0x80)

/* Both are wait4(2) underneath. ECHILD still reaches the caller when there is
   genuinely nothing to reap — it is now the KERNEL saying so rather than crtl
   asserting it, which is the difference that matters. */
int wait(int *status);
int waitpid(int pid, int *status, int options);

/* wait4/wait3: the same reap, with the child's resource usage written into
   *rusage when it is not NULL. `struct rusage' comes from <sys/resource.h>,
   which this header does NOT include -- glibc does not either, and a program
   that wants the rusage form includes it itself. The pointer is declared void*
   here for exactly that reason: it keeps the declaration usable in a TU that
   has never seen the struct, which is what wait4(pid, st, opt, NULL) callers
   are, and the kernel is the only thing that reads through it.

   wait3(st, opt, ru) is wait4(-1, st, opt, ru) -- BSD's older spelling, still
   the default busybox assumes (include/platform.h: HAVE_WAIT3 1) and still
   published by glibc, which is why it is here rather than left to the
   program's own fallback. */
int wait4(int pid, int *status, int options, void *rusage);
int wait3(int *status, int options, void *rusage);

#endif
