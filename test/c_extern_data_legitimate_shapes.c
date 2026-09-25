/* The control for c_undefined_extern_data_is_refused.c: every legitimate
 * `extern` variable shape must still compile. Covered: an extern whose
 * definition comes LATER in the file, a block-scope extern, an extern used
 * only in sizeof, a declared but unused extern, and names crtl's headers
 * declare and crtl defines (environ, opterr, optind, optarg, errno).
 * Values are gcc's. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
extern int later;
extern int unused_ghost;
extern char **environ;
extern int opterr, optind;
extern char *optarg;
int f(void) { extern int blockx; return blockx + later; }
int later = 5;
int blockx = 7;
int main(void) {
  printf("%d %d %d %d %d\n", f(), (int)sizeof(unused_ghost), environ != 0, opterr, optind);
  (void)optarg; errno = 0; printf("%d\n", errno);
  return 0;
}
