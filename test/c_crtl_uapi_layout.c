/* SPDX-License-Identifier: Zlib */
/* <linux/fb.h> and <mtd/ubi-user.h>: ioctl numbers AND struct LAYOUTS,
   diffed against gcc.

   THE LAYOUT ROWS ARE THE POINT. FBIOGET_VSCREENINFO fills the caller's buffer
   field by field, so a struct with one field of the wrong width reads every
   field after it from the wrong offset -- and nothing errors. busybox's
   fbsplash.c then computes a pixel address from xres, line_length and
   bits_per_pixel and writes into a mapped framebuffer, so a shifted field is a
   wild store rather than a wrong picture. A constants-only test cannot see any
   of that.

   THE SIZE OF fb_fix_screeninfo IS DIFFERENT ON 32- AND 64-BIT USERSPACE ON
   PURPOSE, because smem_start and mmio_start are pointers-as-integers in the
   kernel's own header. That is why this file prints sizeof and offsetof rather
   than comparing against written-down numbers: the Makefile diffs pxx against
   gcc on the SAME width, so the assertion holds at both without carrying a
   per-target table. Writing those two fields as uint64_t would have made
   x86-64 agree and i386 disagree, and i386 is the target this header was
   needed for.

   EVERY OFFSET busybox READS IS LISTED, not a sample. `.red', `.green' and
   `.blue' are nested fb_bitfields and their sub-offsets are listed too --
   getting fb_bitfield's own size wrong shifts everything after `grayscale'
   while leaving xres and yres correct, which is precisely the failure a
   spot-check of the first few fields would pass. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <stddef.h>
#include <sys/ioctl.h>
/* THE HOST <mtd/ubi-user.h> DOES NOT INCLUDE WHAT DEFINES _IOW -- neither the
   glibc copy nor the kernel UAPI original does, both including only
   <linux/types.h>. Callers get it from <sys/ioctl.h>, which is true under crtl
   and NOT true under glibc, where _IOW lives in <linux/ioctl.h>. So the guard
   below is the portable spelling, not a workaround: it fires for gcc and is
   skipped for crtl, whose <sys/ioctl.h> already carries the macro. */
#ifndef _IOW
#include <linux/ioctl.h>
#endif
#include <linux/fb.h>
#include <mtd/ubi-user.h>

#define P(x)   printf("%-34s %ld\n", #x, (long)(x))
#define O(t,f) printf("offsetof %-25s %ld\n", #t "." #f, (long)offsetof(struct t, f))

int main(void)
{
  P(FBIOGET_VSCREENINFO); P(FBIOPUT_VSCREENINFO); P(FBIOGET_FSCREENINFO);
  P(FBIOGETCMAP); P(FBIOPUTCMAP); P(FBIOPAN_DISPLAY); P(FBIOBLANK);
  P(FB_TYPE_PACKED_PIXELS); P(FB_TYPE_PLANES); P(FB_TYPE_FOURCC);
  P(FB_VISUAL_TRUECOLOR); P(FB_VISUAL_PSEUDOCOLOR); P(FB_VISUAL_FOURCC);
  P(FB_ACTIVATE_NOW); P(FB_ACTIVATE_MASK); P(FB_VMODE_MASK); P(FB_ACCEL_NONE);

  P(sizeof(struct fb_bitfield));
  P(sizeof(struct fb_fix_screeninfo));
  P(sizeof(struct fb_var_screeninfo));
  P(sizeof(struct fb_cmap));

  O(fb_bitfield, offset); O(fb_bitfield, length); O(fb_bitfield, msb_right);

  O(fb_fix_screeninfo, id);         O(fb_fix_screeninfo, smem_start);
  O(fb_fix_screeninfo, smem_len);   O(fb_fix_screeninfo, type);
  O(fb_fix_screeninfo, type_aux);   O(fb_fix_screeninfo, visual);
  O(fb_fix_screeninfo, xpanstep);   O(fb_fix_screeninfo, ypanstep);
  O(fb_fix_screeninfo, ywrapstep);  O(fb_fix_screeninfo, line_length);
  O(fb_fix_screeninfo, mmio_start); O(fb_fix_screeninfo, mmio_len);
  O(fb_fix_screeninfo, accel);      O(fb_fix_screeninfo, capabilities);

  O(fb_var_screeninfo, xres);           O(fb_var_screeninfo, yres);
  O(fb_var_screeninfo, xres_virtual);   O(fb_var_screeninfo, yres_virtual);
  O(fb_var_screeninfo, xoffset);        O(fb_var_screeninfo, yoffset);
  O(fb_var_screeninfo, bits_per_pixel); O(fb_var_screeninfo, grayscale);
  O(fb_var_screeninfo, red);            O(fb_var_screeninfo, green);
  O(fb_var_screeninfo, blue);           O(fb_var_screeninfo, transp);
  O(fb_var_screeninfo, nonstd);         O(fb_var_screeninfo, activate);
  O(fb_var_screeninfo, height);         O(fb_var_screeninfo, width);
  O(fb_var_screeninfo, accel_flags);    O(fb_var_screeninfo, pixclock);
  O(fb_var_screeninfo, left_margin);    O(fb_var_screeninfo, right_margin);
  O(fb_var_screeninfo, upper_margin);   O(fb_var_screeninfo, lower_margin);
  O(fb_var_screeninfo, hsync_len);      O(fb_var_screeninfo, vsync_len);
  O(fb_var_screeninfo, sync);           O(fb_var_screeninfo, vmode);
  O(fb_var_screeninfo, rotate);         O(fb_var_screeninfo, colorspace);
  O(fb_var_screeninfo, reserved);

  O(fb_cmap, start); O(fb_cmap, len); O(fb_cmap, red);
  O(fb_cmap, green); O(fb_cmap, blue); O(fb_cmap, transp);

  /* <mtd/ubi-user.h>. THE IOCTL NUMBERS ARE THE LAYOUT ASSERTION HERE, not a
     separate one: _IOW folds _IOC_TYPECHECK(size) into the command, so
     UBI_IOCMKVOL printing gcc's number IS `sizeof(struct ubi_mkvol_req)
     matches gcc'. The sizeofs below are printed anyway because a size that
     disagrees names the struct, where a wrong ioctl number names only the
     command -- and a `packed' attribute the frontend silently ignored would
     move four of the five at once. */
  P(UBI_CTRL_IOC_MAGIC); P(UBI_IOC_MAGIC); P(UBI_VOL_IOC_MAGIC);
  P(UBI_MAX_VOLUME_NAME); P(UBI_MAX_RNVOL);
  P(UBI_DEV_NUM_AUTO); P(UBI_VOL_NUM_AUTO);
  P(UBI_DYNAMIC_VOLUME); P(UBI_STATIC_VOLUME);
  P(UBI_VOL_PROP_DIRECT_WRITE); P(UBI_VOL_SKIP_CRC_CHECK_FLG);
  P(UBI_IOCATT); P(UBI_IOCDET);
  P(UBI_IOCMKVOL); P(UBI_IOCRMVOL); P(UBI_IOCRSVOL); P(UBI_IOCRNVOL);
  P(UBI_IOCRPEB); P(UBI_IOCSPEB);
  P(UBI_IOCVOLUP); P(UBI_IOCEBER); P(UBI_IOCEBCH); P(UBI_IOCEBMAP);
  P(UBI_IOCEBUNMAP); P(UBI_IOCEBISMAP); P(UBI_IOCSETVOLPROP);
  P(UBI_IOCVOLCRBLK); P(UBI_IOCVOLRMBLK);

  P(sizeof(struct ubi_attach_req));       P(sizeof(struct ubi_mkvol_req));
  P(sizeof(struct ubi_rsvol_req));        P(sizeof(struct ubi_rnvol_req));
  P(sizeof(struct ubi_leb_change_req));   P(sizeof(struct ubi_map_req));
  P(sizeof(struct ubi_set_vol_prop_req)); P(sizeof(struct ubi_blkcreate_req));

  O(ubi_attach_req, ubi_num);  O(ubi_attach_req, mtd_num);
  O(ubi_attach_req, vid_hdr_offset); O(ubi_attach_req, max_beb_per1024);
  O(ubi_attach_req, disable_fm); O(ubi_attach_req, need_resv_pool);
  O(ubi_mkvol_req, vol_id);    O(ubi_mkvol_req, alignment);
  O(ubi_mkvol_req, bytes);     O(ubi_mkvol_req, vol_type);
  O(ubi_mkvol_req, flags);     O(ubi_mkvol_req, name_len);
  O(ubi_mkvol_req, name);
  O(ubi_rsvol_req, bytes);     O(ubi_rsvol_req, vol_id);
  O(ubi_rnvol_req, count);     O(ubi_rnvol_req, ents);
  O(ubi_set_vol_prop_req, property); O(ubi_set_vol_prop_req, value);
  return 0;
}
