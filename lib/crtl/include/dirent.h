/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_DIRENT_H
#define PXX_CRTL_DIRENT_H 1

/* Directory reading, over the PAL's getdents64. REAL, not a stub.

   `struct dirent` below is the kernel's linux_dirent64 with the flexible name
   turned into a fixed 256-byte array — which is also exactly glibc's layout,
   so a record copied out of the syscall buffer needs no translation beyond the
   name copy.

   NAME_MAX is 255 on Linux, so 256 always holds a name plus its NUL. A longer
   one cannot arrive from the kernel; the reader still bounds the copy rather
   than trusting that, because the alternative to a bound is a stack smash from
   whatever a hostile filesystem returns. */

#include <sys/types.h>
#include <stddef.h>

#define NAME_MAX_DIRENT 255

struct dirent {
  unsigned long long d_ino;
  long long          d_off;
  unsigned short     d_reclen;
  unsigned char      d_type;
  char               d_name[256];
};

/* d_type values (getdents64). DT_UNKNOWN is not an error — some filesystems
   genuinely do not report the type and the caller must stat to find out. */
#define DT_UNKNOWN  0
#define DT_FIFO     1
#define DT_CHR      2
#define DT_DIR      4
#define DT_BLK      6
#define DT_REG      8
#define DT_LNK     10
#define DT_SOCK    12
#define DT_WHT     14

typedef struct __pxx_dir DIR;

DIR *opendir(const char *name);
DIR *fdopendir(int fd);
struct dirent *readdir(DIR *d);
int closedir(DIR *d);
void rewinddir(DIR *d);
int dirfd(DIR *d);

#endif
