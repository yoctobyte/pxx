/* dup / dup2 (feature-crtl-process-file-ops-batch). PalDup2 already existed, so
 * dup2 needed only a __pxx_dup2 bridge; dup is fcntl(F_DUPFD, 0), which IS
 * dup()'s definition rather than a substitute for a missing primitive.
 *
 * Asserted behaviourally — the duplicate must actually read the same file, and
 * dup2 must land on the descriptor it was given — not merely return >= 0.
 * Whole output diffed against the same file built by gcc.
 */
#include <stdio.h>
#include <unistd.h>
#include <string.h>
int main(void) {
  FILE *f; char b[32]; int fd, nd, rc; long n;
  const char *p = "/tmp/pxx_dup_probe.txt";
  f = fopen(p, "wb"); fwrite("dupdata", 1, 7, f); fclose(f);
  f = fopen(p, "rb"); fd = fileno(f);
  nd = dup(fd);
  printf("dup_ok=%d distinct=%d\n", nd >= 0, nd != fd);
  n = read(nd, b, 7); b[n > 0 ? n : 0] = 0;
  printf("dup_reads=[%s]\n", b);
  close(nd);
  /* dup2 onto a specific descriptor */
  nd = 17;
  rc = dup2(fd, nd);
  printf("dup2_ok=%d returns_target=%d\n", rc >= 0, rc == nd);
  lseek(nd, 0, SEEK_SET);
  memset(b, 0, sizeof b);
  n = read(nd, b, 7); b[n > 0 ? n : 0] = 0;
  printf("dup2_reads=[%s]\n", b);
  close(nd); fclose(f); remove(p);
  return 0;
}
