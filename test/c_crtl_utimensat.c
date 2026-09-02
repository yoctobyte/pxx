/* utimensat(2) and futimens(3), the last crtl gap between the busybox userland
   and `touch'. Values diffed against a gcc build of this same source.

   ROW 2 IS THE ONE WITH A WRONG ANSWER AVAILABLE. UTIME_OMIT is not a time; it
   is "leave this field alone", and it travels in tv_nsec beside a tv_sec the
   kernel must ignore. An implementation that normalises the nanosecond fields,
   or that reads the clock itself when it sees a magic value, sets atime to
   something plausible and `touch -m' silently stops meaning what it says.
   Row 2 asserts atime is UNCHANGED from row 1 while mtime moved.

   Row 3 is futimens, which is not a second implementation: futimens(fd, ts) IS
   utimensat(fd, NULL, ts, 0), so the row asserts the two spellings reach the
   same place. Row 4 keeps the failure path honest -- ENOENT, not a silent 0.
   feature-c-crtl-utimensat-and-futimens */
#include <time.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

int main(void) {
  char p[256];
  /* The ABSENT path must not be a bare /tmp literal: two concurrent runs would
     share it, and a stray file left by anything else flips row 4 from ENOENT
     to success. testmgr cannot privatize a path written at RUNTIME, so read
     the directory from the environment -- TESTMGR_TMP first (testmgr launches
     jobs through an env allowlist that $TESTTMP does not survive), TESTTMP
     second (what `make test TESTTMP=$(mktemp -d)` exports), /tmp last so a
     bare run stays byte-identical. */
  char absent[512];
  const char *dir;
  struct stat st;
  struct timespec ts[2];
  int fd, r;

  dir = getenv("TESTMGR_TMP");
  if (!dir) dir = getenv("TESTTMP");
  if (!dir) dir = "/tmp";
  snprintf(p,      sizeof p,      "%s/c_crtl_utimensatXXXXXX", dir);
  snprintf(absent, sizeof absent, "%s/c_crtl_utimensat_absent", dir);

  fd = mkstemp(p);
  close(fd);

  ts[0].tv_sec = 1000000000; ts[0].tv_nsec = 0;
  ts[1].tv_sec = 1100000000; ts[1].tv_nsec = 0;
  r = utimensat(AT_FDCWD, p, ts, 0);
  stat(p, &st);
  printf("1 %d %lld %lld\n", r, (long long)st.st_atime, (long long)st.st_mtime);

  ts[0].tv_sec = 1999999999; ts[0].tv_nsec = UTIME_OMIT;   /* tv_sec ignored */
  ts[1].tv_sec = 1200000000; ts[1].tv_nsec = 0;
  r = utimensat(AT_FDCWD, p, ts, 0);
  stat(p, &st);
  printf("2 %d %lld %lld\n", r, (long long)st.st_atime, (long long)st.st_mtime);

  fd = open(p, O_WRONLY);
  ts[0].tv_sec = 1300000000; ts[0].tv_nsec = 0;
  ts[1].tv_sec = 1400000000; ts[1].tv_nsec = 0;
  r = futimens(fd, ts);
  close(fd);
  stat(p, &st);
  printf("3 %d %lld %lld\n", r, (long long)st.st_atime, (long long)st.st_mtime);

  r = utimensat(AT_FDCWD, absent, ts, 0);
  printf("4 %d %d\n", r, errno);

  unlink(p);
  return 0;
}
