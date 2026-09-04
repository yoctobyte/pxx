/* SPDX-License-Identifier: Zlib */
/* waitpid/wait/wait4 and the W* status macros, diffed against glibc.
 *
 * THE STATUS WORD IS THE POINT, NOT THE RETURN VALUE. Every row here prints
 * what the W* macros make of the status, because the failure this test was
 * written for does not corrupt the return value in a visible way -- it leaves
 * the CALLER'S status word untouched. A row that printed only
 * `waitpid returned the pid' passes while WIFEXITED reads whatever was on the
 * stack, and reports a confident wrong answer about how the child died.
 *
 * SO THE STATUS WORD IS PRE-FILLED WITH 0x5A5A5A5A EVERY TIME. Zero would have
 * been the wrong sentinel: an untouched-but-zeroed status reads as
 * WIFEXITED=1, WEXITSTATUS=0 -- a clean exit -- which is both plausible and
 * indistinguishable from the real thing. The expected value would have
 * collided with the failure value.
 *
 * NO sleep() ANYWHERE. Every ordering this test needs is enforced with a pipe:
 * the child writes a byte when it has reached the state the parent wants to
 * observe, and blocks on a read when the parent needs it to stay alive. A
 * timing-based version of the WNOHANG rows passes on a fast box and flakes on
 * a loaded one, and a flaky row in a cross-target matrix reads as a target
 * bug.
 *
 * THE STOPPED AND CONTINUED ROWS ARE THE ONES A wait4-SHAPED IMPLEMENTATION
 * GETS FOR FREE AND A waitid-SHAPED ONE DOES NOT. waitid reports the same
 * events through si_code (CLD_STOPPED, CLD_CONTINUED) and a conversion has to
 * rebuild the 0x7f / 0xffff encodings the macros read. They are here because
 * they are exactly what such a conversion gets wrong while every exit-status
 * row still passes. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/resource.h>

#define SENTINEL 0x5A5A5A5A

static void show(const char *label, pid_t got, pid_t want, int st, int e)
{
  printf("%-16s ret=%-4s errno=%-2d", label,
         got == want ? "ok" : (got == 0 ? "zero" : "BAD"), e);
  if (st == (int)SENTINEL) {
    printf(" status=UNTOUCHED\n");
    return;
  }
  printf(" exited=%d code=%d signalled=%d sig=%d stopped=%d ssig=%d cont=%d\n",
         WIFEXITED(st) ? 1 : 0, WIFEXITED(st) ? WEXITSTATUS(st) : -1,
         WIFSIGNALED(st) ? 1 : 0, WIFSIGNALED(st) ? WTERMSIG(st) : -1,
         WIFSTOPPED(st) ? 1 : 0, WIFSTOPPED(st) ? WSTOPSIG(st) : -1,
         WIFCONTINUED(st) ? 1 : 0);
}

/* Block until the child writes its ready byte. Returns 0 on success. */
static int waitbyte(int fd)
{
  char c;
  ssize_t n;
  do { n = read(fd, &c, 1); } while (n < 0 && errno == EINTR);
  return n == 1 ? 0 : -1;
}

int main(void)
{
  int st, e;
  pid_t p, w;

  /* 1. An ordinary exit. */
  st = SENTINEL;
  p = fork();
  if (p == 0) _exit(7);
  errno = 0; w = waitpid(p, &st, 0); e = errno;
  show("exit7", w, p, st, e);

  /* 2. Killed by a signal. SIGKILL rather than SIGTERM so no handler, default
     disposition or ignore setting anywhere can change the answer. */
  {
    int rd[2];
    if (pipe(rd) != 0) { perror("pipe"); return 2; }
    st = SENTINEL;
    p = fork();
    if (p == 0) {
      char c = 'x';
      close(rd[0]);
      if (write(rd[1], &c, 1) != 1) _exit(3);
      for (;;) pause();
    }
    close(rd[1]);
    if (waitbyte(rd[0]) != 0) { printf("killed           SETUP FAILED\n"); return 2; }
    kill(p, SIGKILL);
    errno = 0; w = waitpid(p, &st, 0); e = errno;
    show("killed", w, p, st, e);
    close(rd[0]);
  }

  /* 3. WNOHANG while the child is alive: must return 0 and touch nothing.
     4. WNOHANG after it exits: must return the pid. The pipe is what makes
        both deterministic -- the child blocks on a read for row 3 and the
        parent closes the write end to release it for row 4. */
  {
    int go[2], rdy[2];
    if (pipe(go) != 0 || pipe(rdy) != 0) { perror("pipe"); return 2; }
    st = SENTINEL;
    p = fork();
    if (p == 0) {
      char c = 'x';
      close(go[1]); close(rdy[0]);
      if (write(rdy[1], &c, 1) != 1) _exit(3);
      /* Blocks until the parent closes go[1]; then read returns 0. */
      while (read(go[0], &c, 1) < 0 && errno == EINTR) { }
      _exit(11);
    }
    close(go[0]); close(rdy[1]);
    if (waitbyte(rdy[0]) != 0) { printf("nohang-live      SETUP FAILED\n"); return 2; }
    errno = 0; w = waitpid(p, &st, WNOHANG); e = errno;
    show("nohang-live", w, 0, st, e);

    close(go[1]);                    /* let the child run to _exit(11) */
    st = SENTINEL;
    /* Loop rather than sleep: WNOHANG is allowed to answer 0 until the child
       is actually reapable, and the loop is what makes that not a race. */
    do { errno = 0; w = waitpid(p, &st, WNOHANG); e = errno; } while (w == 0);
    show("nohang-exited", w, p, st, e);
    close(rdy[0]);
  }

  /* 5. No children at all: -1 with ECHILD. A row that only checked for -1
        would pass for ENOSYS, which is the defect this file was written for. */
  st = SENTINEL;
  errno = 0; w = waitpid(-1, &st, 0); e = errno;
  printf("%-16s ret=%s errno=%d status=%s\n", "nochild",
         w == -1 ? "minus1" : "BAD", e,
         st == (int)SENTINEL ? "UNTOUCHED" : "written");

  /* 6. Stopped, then continued. Two rows out of one child. */
  {
    int rdy[2];
    if (pipe(rdy) != 0) { perror("pipe"); return 2; }
    st = SENTINEL;
    p = fork();
    if (p == 0) {
      char c = 'x';
      close(rdy[0]);
      if (write(rdy[1], &c, 1) != 1) _exit(3);
      raise(SIGSTOP);
      _exit(5);
    }
    close(rdy[1]);
    if (waitbyte(rdy[0]) != 0) { printf("stopped          SETUP FAILED\n"); return 2; }
    errno = 0; w = waitpid(p, &st, WUNTRACED); e = errno;
    show("stopped", w, p, st, e);

    kill(p, SIGCONT);
    st = SENTINEL;
    errno = 0; w = waitpid(p, &st, WCONTINUED); e = errno;
    show("continued", w, p, st, e);

    st = SENTINEL;
    errno = 0; w = waitpid(p, &st, 0); e = errno;
    show("after-cont", w, p, st, e);
    close(rdy[0]);
  }

  /* 7. wait() is waitpid(-1, ..., 0). */
  st = SENTINEL;
  p = fork();
  if (p == 0) _exit(3);
  errno = 0; w = wait(&st); e = errno;
  show("wait", w, p, st, e);

  /* 8. wait4 with a rusage buffer. The rusage VALUES are not compared -- they
        are timings and differ every run -- but the buffer is pre-filled and
        the row reports whether anything was written, which is the only part
        that is a property of the implementation rather than of the machine. */
  {
    struct rusage ru;
    memset(&ru, 0x5a, sizeof ru);
    st = SENTINEL;
    p = fork();
    if (p == 0) _exit(9);
    errno = 0; w = wait4(p, &st, 0, &ru); e = errno;
    show("wait4-rusage", w, p, st, e);
    {
      size_t i, untouched = 1;
      const unsigned char *q = (const unsigned char *)&ru;
      for (i = 0; i < sizeof ru; i++) if (q[i] != 0x5a) { untouched = 0; break; }
      printf("%-16s rusage=%s\n", "wait4-rusage", untouched ? "UNTOUCHED" : "written");
    }
  }

  /* 9. waitpid for a pid that is not our child: -1/ECHILD, not a hang and not
        a wrong success. pid 1 is init and is never a child of this process. */
  st = SENTINEL;
  errno = 0; w = waitpid(1, &st, WNOHANG); e = errno;
  printf("%-16s ret=%s errno=%d status=%s\n", "notmychild",
         w == -1 ? "minus1" : "BAD", e,
         st == (int)SENTINEL ? "UNTOUCHED" : "written");
  return 0;
}
