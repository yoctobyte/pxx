/* pxx's own <sys/ioctl.h> must supply the _IOC request-encoding family, the way
   glibc's does through <bits/ioctls.h> -> <asm/ioctl.h>. Real programs spell
   their own ioctl numbers with these rather than including a linux/ uapi
   header — busybox writes `#define FDGETPRM _IOR(2, 0x04, struct
   floppy_struct)` and `_IOW(BTRFS_IOCTL_MAGIC, 9, int)` in its own sources.
   Values oracled against gcc -O0 with the host headers. */
#include <sys/ioctl.h>

int printf(const char *, ...);

struct floppy_struct { unsigned int size, sect, head, track; };

int main(void) {
  /* the two busybox call sites, verbatim */
  printf("%lu\n", (unsigned long)_IOW(0x94, 9, int));
  printf("%lu\n", (unsigned long)_IOR(2, 0x04, struct floppy_struct));

  /* the other three constructors */
  printf("%lu\n", (unsigned long)_IO(2, 0x01));
  printf("%lu\n", (unsigned long)_IOWR('t', 3, long));

  /* the size field really is the type's size, not a copy of nr */
  printf("%lu %lu\n", (unsigned long)_IOC_SIZE(_IOR(2, 4, struct floppy_struct)),
                      (unsigned long)_IOC_SIZE(_IOW(0x94, 9, int)));

  /* round-trip the four fields back out */
  printf("%lu %lu %lu\n", (unsigned long)_IOC_DIR(_IOW(0x94, 9, int)),
                          (unsigned long)_IOC_TYPE(_IOW(0x94, 9, int)),
                          (unsigned long)_IOC_NR(_IOW(0x94, 9, int)));

  /* TCGETS/FIONREAD, already present, must keep their asm-generic values */
  printf("%d %d\n", TCGETS, FIONREAD);
  return 0;
}
