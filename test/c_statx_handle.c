/* SPDX-License-Identifier: Zlib */
/* struct statx / file_handle / open_how layouts, field by field, and real
   calls: statx on a file against stat(), name_to_handle_at, open_how via
   openat2's struct. Row c_statx26, against gcc + glibc.
   feature-crtl-statx-file-handle-open-how */
#define _GNU_SOURCE
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/uio.h>

#define O(T, f) printf("%s.%s %zu\n", #T, #f, offsetof(struct T, f))

int main(int argc, char **argv)
{
    struct statx sx;
    struct stat st;
    struct iovec iv;
    unsigned char hbuf[sizeof(struct file_handle) + MAX_HANDLE_SZ];
    struct file_handle *fh = (struct file_handle *)hbuf;
    int mnt = -1, r;
    const char *path = argc > 1 ? argv[1] : "/";

    printf("sizes statx %zu ts %zu fh %zu how %zu\n", sizeof(struct statx),
           sizeof(struct statx_timestamp), sizeof(struct file_handle), sizeof(struct open_how));
    O(statx, stx_mask); O(statx, stx_blksize); O(statx, stx_attributes); O(statx, stx_nlink);
    O(statx, stx_uid); O(statx, stx_gid); O(statx, stx_mode); O(statx, stx_ino);
    O(statx, stx_size); O(statx, stx_blocks); O(statx, stx_attributes_mask);
    O(statx, stx_atime); O(statx, stx_btime); O(statx, stx_ctime); O(statx, stx_mtime);
    O(statx, stx_rdev_major); O(statx, stx_rdev_minor); O(statx, stx_dev_major);
    O(statx, stx_dev_minor); O(statx, stx_mnt_id); O(statx, stx_dio_mem_align);
    O(statx, stx_dio_offset_align); O(statx, stx_subvol);
    O(statx_timestamp, tv_sec); O(statx_timestamp, tv_nsec);
    O(file_handle, handle_bytes); O(file_handle, handle_type); O(file_handle, f_handle);
    O(open_how, flags); O(open_how, mode); O(open_how, resolve);
    printf("consts %#x %#x %#x %#x %#x %d\n", STATX_BASIC_STATS, STATX_MNT_ID, STATX_BTIME,
           STATX_ATTR_MOUNT_ROOT, AT_STATX_DONT_SYNC, MAX_HANDLE_SZ);
    printf("resolve %#x %#x\n", RESOLVE_BENEATH, RESOLVE_NO_SYMLINKS);

    memset(&sx, 0, sizeof sx);
    r = statx(AT_FDCWD, path, 0, STATX_BASIC_STATS | STATX_MNT_ID, &sx);
    if (r != 0 || stat(path, &st) != 0) { printf("statx failed %d\n", errno); return 1; }
    printf("statx basic %d ino %d size %d mode %d nlink %d mnt %d\n",
           (sx.stx_mask & STATX_BASIC_STATS) == STATX_BASIC_STATS,
           sx.stx_ino == (unsigned long long)st.st_ino, sx.stx_size == (unsigned long long)st.st_size,
           sx.stx_mode == st.st_mode, sx.stx_nlink == st.st_nlink, sx.stx_mnt_id != 0);
    errno = 0;
    r = statx(AT_FDCWD, "/nonexistent/statx", 0, STATX_BASIC_STATS, &sx);
    printf("missing %d enoent %d\n", r, errno == ENOENT);

    fh->handle_bytes = MAX_HANDLE_SZ;
    r = name_to_handle_at(AT_FDCWD, path, fh, &mnt, 0);
    if (r == 0)
        printf("handle ok bytes>0 %d mnt>=0 %d\n", fh->handle_bytes > 0, mnt >= 0);
    else
        printf("handle unsupported %d\n", errno == EOPNOTSUPP || errno == ENOSYS);
    iv.iov_base = 0; iv.iov_len = 3;
    printf("iovec %zu\n", iv.iov_len);
    return 0;
}
