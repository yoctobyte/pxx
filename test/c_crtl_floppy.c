/* crtl: <linux/fd.h> -- the floppy driver's ioctls and structs, and the
 * clearest case in the crtl set of AN IOCTL NUMBER THAT CARRIES A STRUCT SIZE.
 *
 * busybox's util-linux/mkfs_vfat.c has the only call: `ioctl(dev, FDGETPRM,
 * &param)', and it branches on whether the call SUCCEEDED, not on what it
 * returned -- success means a real floppy and the geometry comes from the
 * driver, failure means a loop device, an image or a regular file and the
 * geometry is computed. FDGETPRM is _IOR(2, 0x04, struct floppy_struct), so
 * the struct's SIZE is inside the request number. Drop one field from the
 * struct and the number changes, the kernel does not recognise it, the ioctl
 * fails, and mkfs.vfat concludes "not a floppy" while standing on one. A
 * subset of this header is not a smaller header; it is a different ioctl.
 *
 * ROWS 1, 2 AND 5 MUST DIFFER ON i386 AND THAT IS THE POINT OF THE CROSS ROW.
 * floppy_struct ends in a `const char *name', so it is 32 bytes natively and
 * 28 on i386 -- and because the size is in the number, FDGETPRM moves with it,
 * 0x80200204 against 0x801c0204. Rows 3, 4 and 6 are plain constants and do
 * not move, which is what says the split is the pointer width and nothing
 * else.
 *
 * Every row diffed against gcc/glibc, natively and with `gcc -m32'.
 */
#include <stdio.h>
#include <stddef.h>
#include <linux/fd.h>

int main(void)
{
  printf("1 %d %d\n", (int)sizeof(struct floppy_struct),
         (int)offsetof(struct floppy_struct, name));
  printf("2 %lx %lx %lx\n", (unsigned long)FDGETPRM, (unsigned long)FDSETPRM,
         (unsigned long)FDDEFPRM);
  printf("3 %d %d %d %d\n", FD_STRETCH, FD_SWAPSIDES, FD_ZEROBASED,
         FD_SECTBASEMASK);
  printf("4 %d %d %d\n", FD_2M, FD_SIZECODEMASK, FD_PERP);
  printf("5 %d %d\n", (int)sizeof(struct floppy_drive_params),
         (int)sizeof(struct floppy_drive_struct));
  /* FDFLUSH and FDRESET take no argument, so these two are the control: an
     _IO() number has no size field and must NOT move with the width. */
  printf("6 %lx %lx\n", (unsigned long)FDFLUSH, (unsigned long)FDRESET);
  return 0;
}
