/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_VESA_H
#define PXX_CRTL_LINUX_VESA_H 1

/* <linux/vesa.h> -- the VESA display power levels. <linux/fb.h> builds
   FBIOBLANK's argument values from these. They are kernel ABI numbers:
   hsync and vsync suspend are separate bits, and powerdown is both. Each
   enumerator has a same-named macro too, as in the kernel's header. */
enum vesa_blank_mode {
  VESA_NO_BLANKING   = 0,
  VESA_VSYNC_SUSPEND = 1,
  VESA_HSYNC_SUSPEND = 2,
  VESA_POWERDOWN     = VESA_VSYNC_SUSPEND | VESA_HSYNC_SUSPEND,
  VESA_BLANK_MAX     = VESA_POWERDOWN
};
#define VESA_NO_BLANKING   VESA_NO_BLANKING
#define VESA_VSYNC_SUSPEND VESA_VSYNC_SUSPEND
#define VESA_HSYNC_SUSPEND VESA_HSYNC_SUSPEND
#define VESA_POWERDOWN     VESA_POWERDOWN

#endif
