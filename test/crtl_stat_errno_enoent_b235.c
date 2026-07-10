/* b235 (task-sqlite-libc-free-runtime-bringup, Track B): crtl stat/lstat/fstat
   must set errno on failure. The PAL stat calls return the raw syscall result
   (0 or -errno); the crtl wrappers discarded it, so errno kept a stale value.
   sqlite's path resolver (appendOnePathElement) lstat()s each element and treats
   `errno==ENOENT` as "does not exist yet" (fine) vs any other errno as a real
   error -> SQLITE_CANTOPEN. A missing file with stale errno made sqlite3_open of
   a non-:memory: db fail. Now the wrappers set errno=-r. Exit 42 = pass. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "unistd.c"
#include "sys/stat.c"
#include "sys/stat.h"
#include "unistd.h"
#include "errno.h"

int main(void) {
    struct stat st;
    /* A path that cannot exist. stat/lstat must fail AND set errno = ENOENT. */
    const char *nope = "/tmp/pxx_b235_no_such_dir_zzz/nope.file";
    errno = 0;
    if (stat(nope, &st) != -1) return 1;
    if (errno != ENOENT) return 2;
    errno = 0;
    if (lstat(nope, &st) != -1) return 3;
    if (errno != ENOENT) return 4;
    /* fstat on a bogus fd fails with EBADF (9). */
    errno = 0;
    if (fstat(999999, &st) != -1) return 5;
    if (errno != EBADF) return 6;
    /* A path that DOES exist still succeeds. */
    if (stat("/tmp", &st) != 0) return 7;
    return 42;
}
