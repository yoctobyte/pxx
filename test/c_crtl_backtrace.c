/* backtrace() from <execinfo.h>: the return addresses from its caller
 * outwards, here three nested calls. Each address must lie just after the
 * start of the function it returns INTO (inner, middle, outer, in that
 * order); a function is far less than 4 KiB long, so "within 4 KiB of its
 * start" pins each to the right function whatever order the functions are
 * laid out in. backtrace_symbols gives one string per address in one block,
 * and backtrace_symbols_fd one line per address. The expected output is
 * gcc+glibc's for the same source. */
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int in(void *ret, void *fn) {
  long d = (char *)ret - (char *)fn;
  return d > 0 && d < 4096;
}

__attribute__((noinline)) static int inner(void **pc) { return backtrace(pc, 16); }
__attribute__((noinline)) static int middle(void **pc) { int n = inner(pc); return n; }
__attribute__((noinline)) static int outer(void **pc) { int n = middle(pc); return n; }

int main(void) {
  void *pc[16];
  int n = outer(pc), i, ok = 1, fds[2];
  char **sym, buf[4096];
  long got;
  printf("at least four frames: %d\n", n >= 4);
  printf("inner middle outer: %d %d %d\n", in(pc[0], (void *)inner), in(pc[1], (void *)middle),
         in(pc[2], (void *)outer));
  printf("then main: %d\n", in(pc[3], (void *)main));
  printf("a short buffer is filled and no more: %d\n", outer(pc) >= 4 && backtrace(pc, 2) == 2);
  n = outer(pc);
  sym = backtrace_symbols(pc, n);
  for (i = 0; sym && i < n; i++)
    if (!strstr(sym[i], "0x")) ok = 0;
  printf("symbols: %d\n", sym != 0 && ok);
  free(sym);
  if (pipe(fds)) return 1;
  backtrace_symbols_fd(pc, 3, fds[1]);
  close(fds[1]);
  got = read(fds[0], buf, sizeof buf - 1);
  buf[got > 0 ? got : 0] = 0;
  for (i = 0, ok = 0; buf[i]; i++)
    if (buf[i] == '\n') ok++;
  printf("fd lines: %d\n", ok);
  return 0;
}
