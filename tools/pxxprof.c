/* pxxprof: a sampling profiler that works where the usual ones do not.
 *
 * On plexus `perf` is refused (perf_event_paranoid = 4) and yama
 * ptrace_scope = 1 forbids attaching to anything that is not a descendant, so
 * gdb cannot attach either. This forks the target ITSELF, PTRACE_SEIZEs its own
 * child, and samples RIP with PTRACE_INTERRUPT on a timer -- no privileges
 * needed, and it works on any binary, pxx's own custom-written ELF included.
 *
 *   cc -O2 -o tools/pxxprof tools/pxxprof.c
 *   tools/pxxprof out.txt 300 ./compiler/pascal26 prog.pas /tmp/out
 *   python3 tools/pxxprof_symbolize.py syms.txt out.txt | head -30
 *
 * tools/pxxprof_symbolize.py's header says how to build syms.txt, for an FPC
 * binary (nm) and for a pxx one (DWARF, since pxx emits no symtab).
 *
 * TWO TRAPS, each of which cost real turns once:
 *  - samples that fall OUTSIDE .text are in the vDSO, and their share swings
 *    8 percent to 38 percent between runs of the SAME binary. Exclude them;
 *    never read them as time. pxxprof_symbolize.py buckets them separately.
 *  - FPC's -pg plus gprof gives usable CALL COUNTS and useless TIMES here
 *    (three samples for 1.03 s of user time). Read the counts, not the
 *    percentages -- which is what the debugging playbook already tells you.
 *
 * usage: pxxprof <out.txt> <interval_us> <prog> [args...]
 * feature-opt-o3-register-pressure
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/types.h>

int main(int argc, char **argv) {
  if (argc < 4) { fprintf(stderr, "usage: pxxprof out.txt interval_us prog [args]\n"); return 2; }
  const char *out = argv[1];
  long iv = atol(argv[2]);
  pid_t pid = fork();
  if (pid == 0) {
    /* let the parent seize us; stop until it is ready */
    raise(SIGSTOP);
    int devnull = open("/dev/null", 1);
    if (devnull >= 0) { dup2(devnull, 1); }
    execv(argv[3], &argv[3]);
    _exit(127);
  }
  int st;
  waitpid(pid, &st, WUNTRACED);
  if (ptrace(PTRACE_SEIZE, pid, 0, 0) < 0) { perror("seize"); kill(pid, SIGKILL); return 1; }
  kill(pid, SIGCONT);

  FILE *f = fopen(out, "w");
  struct timespec ts; ts.tv_sec = iv / 1000000; ts.tv_nsec = (iv % 1000000) * 1000;
  long n = 0;
  for (;;) {
    nanosleep(&ts, NULL);
    if (ptrace(PTRACE_INTERRUPT, pid, 0, 0) < 0) break;
    pid_t w = waitpid(pid, &st, 0);
    if (w < 0 || WIFEXITED(st) || WIFSIGNALED(st)) break;
    struct user_regs_struct r;
    if (ptrace(PTRACE_GETREGS, pid, 0, &r) == 0) { fprintf(f, "%llx\n", (unsigned long long)r.rip); n++; }
    if (ptrace(PTRACE_CONT, pid, 0, 0) < 0) break;
  }
  fclose(f);
  while (waitpid(pid, &st, 0) > 0) { if (WIFEXITED(st) || WIFSIGNALED(st)) break; }
  fprintf(stderr, "pxxprof: %ld samples -> %s\n", n, out);
  return 0;
}
