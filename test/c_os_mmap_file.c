/* mmap of a file under a translated --os (on NT: CreateFileMappingW and
   MapViewOfFile in compiler/builtin/winabi.pas). A shared writable mapping
   writes through to the file, a private one does not, an offset that is a
   page but not a 64 KiB multiple lands on the right byte, a read-only one
   reads, msync and munmap answer 0, and a mapping past the end of the file
   still maps its first part. Prints only what is the same on Linux. */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
int main(void) {
  const char *path = "c_os_mmap_file.tmp";
  int fd, i;
  char *p, b[16];
  fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) { printf("open failed\n"); return 1; }
  for (i = 0; i < 100000; i++) { char c = 'a' + i % 26; if (write(fd, &c, 1) != 1) { printf("write failed\n"); return 1; } }
  p = mmap(0, 100000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (p == MAP_FAILED) { printf("shared mmap failed\n"); return 1; }
  printf("shared reads %.5s ... %c\n", p, p[99999]);
  memcpy(p + 10, "XYZ", 3);
  printf("msync %d\n", msync(p, 100000, MS_SYNC));
  printf("munmap %d\n", munmap(p, 100000));
  pread(fd, b, 5, 8); b[5] = 0;
  printf("file after shared write: %s\n", b);
  p = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
  if (p == MAP_FAILED) { printf("private mmap failed\n"); return 1; }
  p[0] = '#';
  printf("private sees %c\n", p[0]);
  munmap(p, 4096);
  pread(fd, b, 1, 0); b[1] = 0;
  printf("file after private write: %s\n", b);
  p = mmap(0, 100, PROT_READ, MAP_SHARED, fd, 8192);
  if (p == MAP_FAILED) { printf("offset mmap failed\n"); return 1; }
  printf("offset 8192 reads %c (want %c)\n", p[0], 'a' + 8192 % 26);
  munmap(p, 100);
  p = mmap(0, 200000, PROT_READ, MAP_PRIVATE, fd, 0);
  printf("past the end maps %d, first %c\n", p != MAP_FAILED, p != MAP_FAILED ? p[0] : '?');
  if (p != MAP_FAILED) munmap(p, 200000);
  close(fd);
  unlink(path);
  return 0;
}
