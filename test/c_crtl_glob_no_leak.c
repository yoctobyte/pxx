/* SPDX-License-Identifier: Zlib */
/* glob()/globfree() in a loop, under -dPXX_ALLOC_CENSUS.
 *
 * THIS IS A DIFFERENT ASSERTION CLASS FROM c_crtl_glob.c AND NEITHER CAN
 * SUBSTITUTE FOR THE OTHER. A leak does not corrupt anything: glob() returns
 * the right paths, globfree() returns, and every one of that file's 37 value
 * rows passes byte-identically to glibc while the process never gives a byte
 * back. Only a count of allocations against frees can see it, which is why
 * this file asserts nothing about the paths at all.
 *
 * crtl's malloc/free ride the same mmap-backed pool as the Pascal RTL heap
 * (lib/crtl/src/stdlib.c, via __pxx_malloc), so PXX_ALLOC_CENSUS -- built for
 * the RTL -- reports on C allocations too. That is not a coincidence to rely
 * on quietly: it is the reason this test can exist without valgrind, which is
 * not on this box.
 *
 * THE TREE IS BUILT HERE, not globbed out of /etc or /usr, so the loop does
 * the same amount of work on every box. A probe pointed at the host
 * filesystem is a guard that gets weaker the emptier the machine is, and on a
 * container with no /etc/*.conf it would allocate nothing and pass. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <glob.h>

static void mkf(const char *p)
{
  int fd = creat(p, 0644);
  if (fd < 0) { fprintf(stderr, "creat %s failed\n", p); exit(2); }
  close(fd);
}

int main(int argc, char **argv)
{
  int i, n;
  char nm[32];

  if (argc < 2) { fprintf(stderr, "usage: %s <empty-dir> [iters]\n", argv[0]); return 2; }
  if (chdir(argv[1]) != 0) { perror("chdir"); return 2; }
  n = argc > 2 ? atoi(argv[2]) : 2000;

  if (mkdir("sub", 0755) != 0) { perror("mkdir"); return 2; }
  for (i = 0; i < 24; i++) {
    sprintf(nm, "f%02d.dat", i);  mkf(nm);
    sprintf(nm, "sub/g%02d.txt", i); mkf(nm);
  }

  /* Four shapes, because they take four different paths through glob():
     a plain wildcard, one that descends a directory, one that ends in '/'
     (the stat-and-keep-the-slash arm), and one that matches nothing (the
     GLOB_NOCHECK arm, which allocates the pattern itself). A loop over one
     shape would leave three arms unmeasured. */
  for (i = 0; i < n; i++) {
    glob_t g;
    memset(&g, 0, sizeof g); glob("*.dat",      0,             0, &g); globfree(&g);
    memset(&g, 0, sizeof g); glob("sub/*.txt",  GLOB_MARK,     0, &g); globfree(&g);
    memset(&g, 0, sizeof g); glob("*/",         0,             0, &g); globfree(&g);
    memset(&g, 0, sizeof g); glob("zzz*",       GLOB_NOCHECK,  0, &g); globfree(&g);
  }
  printf("GLOBLEAK ok %d iterations\n", n);
  return 0;
}
