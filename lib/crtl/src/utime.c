/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: POSIX utime().
 *
 * One path, not a second: utime(file, t) IS utimensat(AT_FDCWD, file, ts, 0)
 * with whole seconds, which is how glibc implements it too, and a NULL `times'
 * is utimensat's own NULL -- "both to now" -- so there is nothing to translate.
 */
#include <utime.h>
#include <fcntl.h>
#include <time.h>

int utime(const char *file, const struct utimbuf *times) {
  struct timespec ts[2];
  if (!times) return utimensat(AT_FDCWD, file, 0, 0);
  ts[0].tv_sec = times->actime;  ts[0].tv_nsec = 0;
  ts[1].tv_sec = times->modtime; ts[1].tv_nsec = 0;
  return utimensat(AT_FDCWD, file, ts, 0);
}
