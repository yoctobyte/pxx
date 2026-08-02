/* struct stat's fields (bug-b-crtl-stat-nlink-hardcoded).
 *
 * crtl's fill() hardcoded st_nlink to 1, st_uid/st_gid/st_rdev to 0, and gave
 * st_atime and st_ctime the value of MTIME — silently, so a caller comparing
 * access time, or spotting a hard link by nlink > 1, got a plausible wrong
 * answer. statx returns all of them; the PAL simply never carried them.
 *
 * Asserted through OBSERVABLE consequences rather than field presence: nlink
 * must rise to 2 when a hard link is made and fall back when it is removed, a
 * directory's nlink must count its subdirectories, and both names must share an
 * inode. Whole output diffed against the same file built by gcc.
 *
 * Uses geteuid(), not getuid() — the latter is not declared in crtl (recorded
 * as a gap, not worked around here).
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
int main(void) {
  struct stat a, b, d; FILE *f; int rc;
  const char *dir = "/tmp/pxx_stat_probe";
  const char *p1 = "/tmp/pxx_stat_probe/f.txt";
  const char *p2 = "/tmp/pxx_stat_probe/h.txt";
  mkdir(dir, 0755);
  f = fopen(p1, "wb"); fwrite("x", 1, 1, f); fclose(f);
  rc = stat(p1, &a);
  printf("before: nlink=%d\n", rc == 0 ? (int)a.st_nlink : -1);
  link(p1, p2);
  rc = stat(p1, &a); printf("after_link_orig=%d\n", rc == 0 ? (int)a.st_nlink : -1);
  rc = stat(p2, &b); printf("after_link_new=%d\n",  rc == 0 ? (int)b.st_nlink : -1);
  printf("same_inode=%d\n", a.st_ino == b.st_ino);
  unlink(p2);
  rc = stat(p1, &a); printf("after_unlink=%d\n", rc == 0 ? (int)a.st_nlink : -1);
  /* a directory's link count reflects its subdirectories */
  mkdir("/tmp/pxx_stat_probe/sub", 0755);
  rc = stat(dir, &d); printf("dir_nlink=%d\n", rc == 0 ? (int)d.st_nlink : -1);
  /* ownership is the real uid/gid, not zero */
  printf("uid_matches=%d uid_nonzero=%d\n",
         a.st_uid == geteuid(), a.st_uid != 0);
  /* the three timestamps must be distinct fields, not all mtime */
  printf("times_present=%d %d %d\n", a.st_atime > 0, a.st_mtime > 0, a.st_ctime > 0);
  rmdir("/tmp/pxx_stat_probe/sub"); unlink(p1); rmdir(dir);
  return 0;
}
