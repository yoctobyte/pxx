/* mallinfo2 / mallinfo report the allocator's own numbers in glibc's layout
   (arena = mapped, uordblks = live, fordblks = the rest), and open64 is
   declared by <fcntl.h>. e2fsprogs (e2fsck -t, unix_io.c). Expected = gcc's. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <malloc.h>
#include <fcntl.h>
#include <unistd.h>
int main(void) {
  struct mallinfo2 a = mallinfo2();
  char *p = malloc(1 << 20);
  for (int i = 0; i < (1 << 20); i += 4096) p[i] = 1;
  struct mallinfo2 b = mallinfo2();
  struct mallinfo c = mallinfo();
  /* in use = uordblks + hblkhd: glibc mmaps a 1 MiB block (hblkhd), crtl has no mmap tier */
  printf("in use grew by >= 1 MiB: %s\n", (b.uordblks + b.hblkhd) - (a.uordblks + a.hblkhd) >= (1u << 20) ? "yes" : "no");
  printf("arena >= uordblks: %s\n", b.arena >= b.uordblks ? "yes" : "no");
  printf("fordblks = arena - uordblks: %s\n", b.fordblks == b.arena - b.uordblks ? "yes" : "no");
  printf("mallinfo agrees: %s\n", (size_t)c.uordblks == b.uordblks ? "yes" : "no");
  free(p);
  int fd = open64("/proc/self/stat", O_RDONLY);
  printf("open64: %s\n", fd >= 0 ? "ok" : "fail");
  close(fd);
  return 0;
}
