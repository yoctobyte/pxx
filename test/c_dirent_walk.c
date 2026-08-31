/* SPDX-License-Identifier: Zlib */
/*
 * crtl's <dirent.h>, over the PAL's getdents64 -- REAL, not stubs. Every row
 * here is a differential against a glibc-built binary of this same file; the
 * expected string in the Makefile is that binary's output.
 *
 * The row that earned this file is `notdir`. Without an eager first
 * getdents64, opendir("<a regular file>") SUCCEEDED here and failed with
 * ENOTDIR under glibc -- a wrong ANSWER, not a crash, and exactly the shape a
 * directory walker mistakes for an empty directory.
 *
 * No path is ever printed: an absolute /tmp in an EXPECTED string is rewritten
 * by testmgr but the same path in the SOURCE is not, so such a row cannot fail
 * locally and always fails on the sweeping host.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

static int cmp(const void *a, const void *b)
{
  return strcmp(*(char *const *)a, *(char *const *)b);
}

/* d_type is advisory: a filesystem that does not carry it reports DT_UNKNOWN,
   and both glibc and we pass that through. So assert MEMBERSHIP in the
   plausible set rather than a fixed value -- which still catches the failure
   this field actually has, reading it at the wrong byte offset. */
static int type_ok(unsigned char t, int wantdir)
{
  if (t == DT_UNKNOWN) return 1;
  return wantdir ? (t == DT_DIR) : (t == DT_REG);
}

int main(int argc, char **argv)
{
  char tmpl[512];
  char path[600];
  const char *base = argc > 1 ? argv[1] : ".";
  const char *files[3];
  char *dir;
  char *names[64];
  unsigned char types[64];
  unsigned long long inos[64];
  int n = 0, i, j, fd, rewound = 0, typesok = 1, inosok = 1;
  DIR *d;
  struct dirent *e;
  FILE *f;

  files[0] = "alpha"; files[1] = "bb"; files[2] = "ccc";

  snprintf(tmpl, sizeof tmpl, "%s/pxxdirXXXXXX", base);
  dir = mkdtemp(tmpl);
  if (!dir) { printf("mkdtemp failed errno=%d\n", errno); return 1; }

  for (i = 0; i < 3; i++) {
    snprintf(path, sizeof path, "%s/%s", dir, files[i]);
    f = fopen(path, "w");
    if (!f) { printf("create failed errno=%d\n", errno); return 1; }
    fclose(f);
  }

  d = opendir(dir);
  printf("opendir: %d\n", d != 0);
  if (!d) return 1;
  printf("dirfd>=0: %d\n", dirfd(d) >= 0);

  errno = 0;
  while ((e = readdir(d)) != 0) {
    if (n >= 64) break;
    names[n] = strdup(e->d_name);
    types[n] = (unsigned char)e->d_type;
    inos[n]  = (unsigned long long)e->d_ino;
    n++;
  }
  /* readdir returns NULL for end-of-directory AND for error, so the only way
     to tell them apart is errno -- which means the end path must leave it
     alone. This row is that contract. */
  printf("end errno: %d\n", errno);
  printf("count: %d\n", n);

  for (i = 0; i < n; i++) {
    int wantdir = (strcmp(names[i], ".") == 0 || strcmp(names[i], "..") == 0);
    if (!type_ok(types[i], wantdir)) typesok = 0;
    if (inos[i] == 0) inosok = 0;
  }
  printf("types plausible: %d\n", typesok);
  printf("inodes nonzero: %d\n", inosok);

  /* Sort: getdents64 order is the filesystem's, not ours, and differs between
     a tmpfs and an ext4 -- comparing it would be comparing the kernel. */
  {
    char *sorted[64];
    for (i = 0; i < n; i++) sorted[i] = names[i];
    qsort(sorted, n, sizeof sorted[0], cmp);
    for (i = 0; i < n; i++) printf("[%s]", sorted[i]);
    printf("\n");
  }

  rewinddir(d);
  while (readdir(d) != 0) rewound++;
  printf("rewind same: %d\n", rewound == n);
  printf("closedir: %d\n", closedir(d));

  /* fdopendir over an fd we opened ourselves, and it must reach the same set. */
  fd = open(dir, O_RDONLY);
  d = fdopendir(fd);
  printf("fdopendir: %d\n", d != 0);
  j = 0;
  while (d && readdir(d) != 0) j++;
  printf("fdopendir same: %d\n", j == n);
  if (d) closedir(d);

  errno = 0;
  d = opendir("/nonexistent-pxx-dirent-probe");
  printf("missing: %d ENOENT: %d\n", d == 0, errno == ENOENT);

  /* THE ROW: a regular file is not a directory, and opendir owes its caller
     ENOTDIR rather than a usable-looking DIR that yields nothing. */
  snprintf(path, sizeof path, "%s/%s", dir, files[0]);
  errno = 0;
  d = opendir(path);
  printf("notdir: %d ENOTDIR: %d\n", d == 0, errno == ENOTDIR);
  if (d) closedir(d);

  for (i = 0; i < 3; i++) {
    snprintf(path, sizeof path, "%s/%s", dir, files[i]);
    unlink(path);
  }
  printf("rmdir: %d\n", rmdir(dir));
  return 0;
}
