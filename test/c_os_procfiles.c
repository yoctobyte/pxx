/* The /proc files a translated --os builds itself (compiler/builtin/
   proctext.inc): /proc/self/fdinfo/N, /proc/mounts and /proc/stat. Prints
   only what is the same on Linux and on every BSD -- that each file opens,
   that fdinfo's ino is fstat's st_ino, that a mount line has six fields and
   one of them is the root, that the cpu line has Linux's ten counters -- so
   the test-<os> targets can compare it with the Linux build's output. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <mntent.h>

static long field(const char *buf, const char *key) {
  const char *p = buf;
  size_t k = strlen(key);
  while (p && *p) {
    if (strncmp(p, key, k) == 0) return atol(p + k);
    p = strchr(p, '\n');
    if (p) p++;
  }
  return -1;
}

int main(void) {
  char path[64], buf[1024];
  struct stat st;
  int fd = open("/dev/null", O_RDONLY);
  int f, n;
  FILE *m;
  struct mntent *e;
  int lines = 0, root = 0, words = 0;
  unsigned long long v[16];

  if (fd < 0 || fstat(fd, &st) != 0) { printf("setup failed\n"); return 1; }
  snprintf(path, sizeof path, "/proc/self/fdinfo/%d", fd);
  f = open(path, O_RDONLY);
  n = f >= 0 ? (int)read(f, buf, sizeof buf - 1) : -1;
  if (f >= 0) close(f);
  if (n <= 0) printf("fdinfo: cannot read\n");
  else {
    buf[n] = 0;
    printf("fdinfo: has mnt_id %d\n", field(buf, "mnt_id:") >= 0);
    printf("fdinfo: ino is st_ino %d\n", field(buf, "ino:") == (long)st.st_ino);
  }

  m = setmntent("/proc/mounts", "r");
  if (!m) printf("mounts: cannot open\n");
  else {
    while ((e = getmntent(m)) != NULL) {
      lines++;
      if (strcmp(e->mnt_dir, "/") == 0) root = 1;
    }
    endmntent(m);
    printf("mounts: some lines %d, root listed %d\n", lines > 0, root);
  }

  m = fopen("/proc/stat", "r");
  if (!m || !fgets(buf, sizeof buf, m)) printf("stat: cannot read\n");
  else {
    words = sscanf(buf, "cpu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu",
                   &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8], &v[9]);
    printf("stat: cpu line with ten counters %d\n", words == 10);
    printf("stat: some idle time %d\n", words == 10 && v[3] > 0);
  }
  if (m) fclose(m);
  return 0;
}
