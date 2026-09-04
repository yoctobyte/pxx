/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_FB_H
#define PXX_CRTL_LINUX_FB_H 1

/* <linux/fb.h> -- the framebuffer ioctls and the two screeninfo records.

   THE STRUCTS ARE IOCTL ARGUMENTS, so their LAYOUT is the contract and not
   just their contents: FBIOGET_VSCREENINFO fills the caller's buffer field by
   field, and a struct with one field of the wrong width reads every field
   after it from the wrong offset. Nothing errors. busybox's
   miscutils/fbsplash.c then computes a pixel address from xres, line_length
   and bits_per_pixel and writes into a mapped framebuffer -- so a shifted
   field is a wild store, not a wrong number on a screen.
   test/c_crtl_fb_layout.c asserts sizeof and every offsetof this file's
   callers touch, against gcc's view of the kernel's own header.

   ONE FIELD IS DELIBERATELY `unsigned long' AND NOT A FIXED WIDTH.
   fb_fix_screeninfo's smem_start and mmio_start are pointers-as-integers in
   the kernel's own header, so the struct is a different size on 32- and 64-bit
   userspace BY DESIGN. Writing them as uint64_t would make x86-64 agree and
   i386 disagree, and i386 is where this header was needed. Same reasoning as
   <sys/statfs.h>'s __statfs_word note.

   WHAT IS NOT HERE, AND WHY. The FB_ACCEL_* registry is ~120 names for
   specific graphics chips, none reachable from anything in this tree; the
   cursor, vblank and console-mapping ioctls need structs with no consumer
   here. A wire layout with no test behind it is a liability, so they are
   absent -- and naming one is a compile error, which says so.

   Found attempting busybox on i386, where there is no host header to fall back
   on. */

#include <stdint.h>

/* Ioctl commands. These are BARE NUMBERS in the kernel's header rather than
   _IOR/_IOW expressions -- fb predates the encoding scheme -- so they are
   copied as the numbers they are. */
#define FBIOGET_VSCREENINFO  0x4600
#define FBIOPUT_VSCREENINFO  0x4601
#define FBIOGET_FSCREENINFO  0x4602
#define FBIOGETCMAP          0x4604
#define FBIOPUTCMAP          0x4605
#define FBIOPAN_DISPLAY      0x4606
#define FBIOGET_CON2FBMAP    0x460F
#define FBIOPUT_CON2FBMAP    0x4610
#define FBIOBLANK            0x4611  /* arg: 0, or a VESA level plus one */
#define FBIO_ALLOC           0x4613
#define FBIO_FREE            0x4614
#define FBIOGET_GLYPH        0x4615
#define FBIOGET_HWCINFO      0x4616
#define FBIOPUT_MODEINFO     0x4617
#define FBIOGET_DISPINFO     0x4618

/* fix.type */
#define FB_TYPE_PACKED_PIXELS      0
#define FB_TYPE_PLANES             1
#define FB_TYPE_INTERLEAVED_PLANES 2
#define FB_TYPE_TEXT               3
#define FB_TYPE_VGA_PLANES         4
#define FB_TYPE_FOURCC             5

/* fix.visual */
#define FB_VISUAL_MONO01             0
#define FB_VISUAL_MONO10             1
#define FB_VISUAL_TRUECOLOR          2
#define FB_VISUAL_PSEUDOCOLOR        3
#define FB_VISUAL_DIRECTCOLOR        4
#define FB_VISUAL_STATIC_PSEUDOCOLOR 5
#define FB_VISUAL_FOURCC             6

/* var.activate */
#define FB_ACTIVATE_NOW      0
#define FB_ACTIVATE_NXTOPEN  1
#define FB_ACTIVATE_TEST     2
#define FB_ACTIVATE_MASK     15
#define FB_ACTIVATE_VBL      16
#define FB_CHANGE_CMAP_VBL   32
#define FB_ACTIVATE_ALL      64
#define FB_ACTIVATE_FORCE    128
#define FB_ACTIVATE_INV_MODE 256

/* var.vmode */
#define FB_VMODE_NONINTERLACED 0
#define FB_VMODE_INTERLACED    1
#define FB_VMODE_DOUBLE        2
#define FB_VMODE_ODD_FLD_FIRST 4
#define FB_VMODE_MASK          255

/* var.sync */
#define FB_SYNC_HOR_HIGH_ACT  1
#define FB_SYNC_VERT_HIGH_ACT 2
#define FB_SYNC_EXT           4
#define FB_SYNC_COMP_HIGH_ACT 8
#define FB_SYNC_BROADCAST     16
#define FB_SYNC_ON_GREEN      32

/* No accelerator. The rest of the FB_ACCEL_* registry is deliberately absent. */
#define FB_ACCEL_NONE 0

struct fb_fix_screeninfo {
  char          id[16];       /* identification, e.g. "VESA VGA" */
  unsigned long smem_start;   /* physical address of the framebuffer */
  uint32_t      smem_len;     /* its length in bytes */
  uint32_t      type;         /* FB_TYPE_* */
  uint32_t      type_aux;     /* interleave, for interleaved planes */
  uint32_t      visual;       /* FB_VISUAL_* */
  uint16_t      xpanstep;     /* 0 if the hardware cannot pan */
  uint16_t      ypanstep;
  uint16_t      ywrapstep;
  uint32_t      line_length;  /* bytes per scanline -- NOT xres * bpp / 8 */
  unsigned long mmio_start;   /* physical address of memory-mapped I/O */
  uint32_t      mmio_len;
  uint32_t      accel;        /* FB_ACCEL_* */
  uint16_t      capabilities;
  uint16_t      reserved[2];
};

struct fb_bitfield {
  uint32_t offset;    /* bit position of the field's low bit */
  uint32_t length;    /* how many bits */
  uint32_t msb_right; /* nonzero if bit 0 is the most significant */
};

struct fb_var_screeninfo {
  uint32_t xres;          /* visible resolution */
  uint32_t yres;
  uint32_t xres_virtual;  /* virtual resolution */
  uint32_t yres_virtual;
  uint32_t xoffset;       /* offset from virtual to visible */
  uint32_t yoffset;

  uint32_t bits_per_pixel;
  uint32_t grayscale;     /* 0 colour, 1 greyscale, >1 a FOURCC */

  struct fb_bitfield red;    /* where each channel sits in a pixel, when */
  struct fb_bitfield green;  /* the visual is true colour; otherwise only */
  struct fb_bitfield blue;   /* .length is meaningful */
  struct fb_bitfield transp;

  uint32_t nonstd;        /* nonzero: a non-standard pixel format */
  uint32_t activate;      /* FB_ACTIVATE_* */
  uint32_t height;        /* physical size in mm, or -1 */
  uint32_t width;
  uint32_t accel_flags;   /* obsolete */

  /* Timing. Everything but pixclock is counted in pixel clocks. */
  uint32_t pixclock;      /* picoseconds per pixel */
  uint32_t left_margin;
  uint32_t right_margin;
  uint32_t upper_margin;
  uint32_t lower_margin;
  uint32_t hsync_len;
  uint32_t vsync_len;
  uint32_t sync;          /* FB_SYNC_* */
  uint32_t vmode;         /* FB_VMODE_* */
  uint32_t rotate;        /* counter-clockwise, in degrees */
  uint32_t colorspace;    /* for FOURCC-based modes */
  uint32_t reserved[4];
};

/* The palette. The four arrays are the CALLER'S; the kernel reads or writes
   `len' entries through them, so this struct's own size says nothing about how
   much memory an FBIOPUTCMAP touches. */
struct fb_cmap {
  uint32_t  start;   /* first entry to set */
  uint32_t  len;     /* how many */
  uint16_t *red;
  uint16_t *green;
  uint16_t *blue;
  uint16_t *transp;  /* may be NULL */
};

#endif /* PXX_CRTL_LINUX_FB_H */
