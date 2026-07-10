/* b234 (task-sqlite-libc-free-runtime-bringup, Track B): LFS _LARGEFILE64_SOURCE
   aliases. sqlite's os_unix.c imports open64/fcntl64/fstat64/lstat64/stat64/mmap64;
   the crtl provided only the base names, so a libc-free sqlite link left them
   undefined. On LP64 the *64 calls are identical to the base ones (off_t already
   64-bit), so the crtl now forwards them. This exercises the file path end to end
   (open64 -> write -> fstat64/stat64) fully libc-free. Exit 42 = pass. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "fcntl.c"
#include "unistd.c"
#include "sys/stat.c"
#include "fcntl.h"
#include "unistd.h"
#include "sys/stat.h"

int main(void) {
    const char *path = "/tmp/pxx_crtl_lfs64_b234.tmp";
    int fd = open64(path, O_CREAT | O_RDWR | O_TRUNC, 0644);
    if (fd < 0) return 1;
    if (write(fd, "hello", 5) != 5) return 2;

    struct stat st;
    if (fstat64(fd, &st) != 0) return 3;
    if (st.st_size != 5) return 4;

    /* fcntl64 advisory-lock veneer resolves and returns without error */
    if (fcntl64(fd, F_SETFD, 0) < 0) return 5;
    close(fd);

    struct stat st2;
    if (stat64(path, &st2) != 0) return 6;
    if (st2.st_size != 5) return 7;
    if (lstat64(path, &st2) != 0) return 8;

    unlink(path);
    return 42;
}
