/* SPDX-License-Identifier: Zlib */
/* struct dirent64 / readdir64 / getdents64: layouts as glibc's, getdents64
   records walked by d_reclen, readdir64 sees the same names, EBADF on a bad
   fd. Row c_dir64_26, against gcc + glibc. feature-crtl-dirent64-and-getdents64 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : ".";
    union { char b[4096]; long long align; } buf;
    struct dirent64 *e;
    DIR *d;
    long n, off;
    int fd, names = 0, names2 = 0, dots = 0;
    ssize_t r;

    printf("dirent64 %zu ino %zu off %zu reclen %zu type %zu name %zu same %d\n",
           sizeof(struct dirent64), offsetof(struct dirent64, d_ino), offsetof(struct dirent64, d_off),
           offsetof(struct dirent64, d_reclen), offsetof(struct dirent64, d_type),
           offsetof(struct dirent64, d_name), sizeof(struct dirent64) == sizeof(struct dirent));
    fd = open(path, O_RDONLY | O_DIRECTORY);
    if (fd < 0) return 1;
    while ((n = (long)getdents64(fd, buf.b, sizeof buf.b)) > 0)
        for (off = 0; off < n; off += ((struct dirent64 *)(buf.b + off))->d_reclen) {
            e = (struct dirent64 *)(buf.b + off);
            names++;
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) dots += e->d_type == DT_DIR;
        }
    printf("getdents64 end %ld dots %d\n", n, dots);
    close(fd);
    d = opendir(path);
    if (!d) return 2;
    while ((e = readdir64(d)) != NULL) names2++;
    closedir(d);
    printf("readdir64 same-count %d nonzero %d\n", names == names2, names > 2);
    errno = 0;
    r = getdents64(-1, buf.b, sizeof buf.b);
    printf("badfd %ld ebadf %d\n", (long)r, errno == EBADF);
    return 0;
}
