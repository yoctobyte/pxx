/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <mtd/ubi-user.h> -- the UBI (Unsorted Block Images) user ioctl
 * surface, for MTD flash on the embedded targets.
 *
 * A PARTIAL SHADOW of the kernel UAPI header, for the reason <linux/fs.h>
 * gives: a cross target has no host UAPI tree, so "the kernel's to ship"
 * becomes "nobody's".
 *
 * EVERY IOCTL HERE ENCODES A sizeof, so a struct that is one field or one
 * attribute wrong produces a NUMBER, not a diagnostic -- _IOW folds
 * _IOC_TYPECHECK(size) into the command, and the kernel rejects the resulting
 * command with EINVAL or, worse, matches a different one. That is why the
 * structs the applet never names are here too: leaving out ubi_rnvol_req to
 * keep the header small would mean either dropping UBI_IOCRNVOL (a header that
 * gives half the ioctls, so the next caller writes its own and gets it wrong)
 * or spelling its size by hand. Both structs and ioctls, or neither.
 *
 * `__attribute__((packed))' IS LOad-BEARING on five of these. ubi_mkvol_req has
 * __s64 bytes at offset 8 and then a 4-byte tail before a 128-byte char array;
 * unpacked, the natural 8-alignment pads it to 144 and the ioctl number changes.
 * ubi_rsvol_req is the clearest case: __s64 + __s32 is 12 packed and 16 not.
 *
 * Found attempting busybox on i386: miscutils/ubi_tools.c (ubiattach,
 * ubidetach, ubimkvol, ubirmvol, ubirsvol, ubiupdatevol, ubirename) stops at
 * this include. It uses UBI_IOCATT/IOCDET/IOCMKVOL/IOCRMVOL/IOCRSVOL/IOCVOLUP,
 * struct ubi_attach_req/ubi_mkvol_req/ubi_rsvol_req, UBI_CTRL_DEV,
 * UBI_DEV_NUM_AUTO, UBI_VOL_NUM_AUTO, UBI_DYNAMIC_VOLUME, UBI_STATIC_VOLUME
 * and UBI_MAX_VOLUME_NAME.
 * bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
 */
#ifndef _CRTL_MTD_UBI_USER_H
#define _CRTL_MTD_UBI_USER_H

#include <linux/types.h>
#include <sys/ioctl.h>

/* The control device an attach/detach goes through. */
#define UBI_CTRL_DEV "/dev/ubi_ctrl"

/* Let the kernel pick the number. Both are -1 and they are NOT
   interchangeable: one is a UBI device index, the other a volume index. */
#define UBI_VOL_NUM_AUTO (-1)
#define UBI_DEV_NUM_AUTO (-1)

/* Not counting the terminating NUL, which the structs allocate separately
   (`char name[UBI_MAX_VOLUME_NAME + 1]'). */
#define UBI_MAX_VOLUME_NAME 127

/* Volume types. */
#define UBI_DYNAMIC_VOLUME 3
#define UBI_STATIC_VOLUME  4

/* Volume properties, for UBI_IOCSETVOLPROP. */
#define UBI_VOL_PROP_DIRECT_WRITE 1

/* Volume flags, for ubi_mkvol_req.flags. */
#define UBI_VOL_SKIP_CRC_CHECK_FLG 0x1
#define UBI_VOL_VALID_FLGS (UBI_VOL_SKIP_CRC_CHECK_FLG)

/* How many volumes one atomic rename may carry. */
#define UBI_MAX_RNVOL 32

/* THREE MAGICS, AND TWO OF THEM ARE THE SAME BYTE. The UBI device and the
   control device both use 'o'; only the volume device differs ('O'). So an
   ioctl aimed at the wrong file descriptor is not caught by the magic -- the
   command number is simply valid for a device that is not listening. */
#define UBI_IOC_MAGIC      'o'
#define UBI_CTRL_IOC_MAGIC 'o'
#define UBI_VOL_IOC_MAGIC  'O'

struct ubi_attach_req {
	__s32 ubi_num;
	__s32 mtd_num;
	__s32 vid_hdr_offset;
	__s16 max_beb_per1024;
	__s8  disable_fm;
	__s8  need_resv_pool;
	__s8  padding[8];
};

struct ubi_mkvol_req {
	__s32 vol_id;
	__s32 alignment;
	__s64 bytes;
	__s8  vol_type;
	__u8  flags;
	__s16 name_len;
	__s8  padding2[4];
	char  name[UBI_MAX_VOLUME_NAME + 1];
} __attribute__((packed));

struct ubi_rsvol_req {
	__s64 bytes;
	__s32 vol_id;
} __attribute__((packed));

struct ubi_rnvol_req {
	__s32 count;
	__s8  padding1[12];
	struct {
		__s32 vol_id;
		__s16 name_len;
		__s8  padding2[2];
		char  name[UBI_MAX_VOLUME_NAME + 1];
	} ents[UBI_MAX_RNVOL];
} __attribute__((packed));

struct ubi_leb_change_req {
	__s32 lnum;
	__s32 bytes;
	__s8  dtype;   /* obsolete, the kernel ignores it; pass 3 */
	__s8  padding[7];
} __attribute__((packed));

struct ubi_map_req {
	__s32 lnum;
	__s8  dtype;   /* obsolete, the kernel ignores it; pass 3 */
	__s8  padding[3];
} __attribute__((packed));

struct ubi_set_vol_prop_req {
	__u8  property;
	__u8  padding[7];
	__u64 value;
} __attribute__((packed));

struct ubi_blkcreate_req {
	__s8 padding[128];
} __attribute__((packed));

/* UBI device ioctls (/dev/ubiN). */
#define UBI_IOCMKVOL _IOW(UBI_IOC_MAGIC, 0, struct ubi_mkvol_req)
#define UBI_IOCRMVOL _IOW(UBI_IOC_MAGIC, 1, __s32)
#define UBI_IOCRSVOL _IOW(UBI_IOC_MAGIC, 2, struct ubi_rsvol_req)
#define UBI_IOCRNVOL _IOW(UBI_IOC_MAGIC, 3, struct ubi_rnvol_req)
#define UBI_IOCRPEB  _IOW(UBI_IOC_MAGIC, 4, __s32)
#define UBI_IOCSPEB  _IOW(UBI_IOC_MAGIC, 5, __s32)

/* WHERE THE LIST STOPS. UBI_IOCECNFO / struct ubi_ecinfo_req (erase-counter
   readout) is deliberately absent. It is a recent addition, nothing in the
   corpus names it, and its last member is a FLEXIBLE ARRAY -- a shape whose
   support in the pxx C frontend is not something this header should be the
   first thing to depend on. Adding it later is a struct and one _IOWR line;
   its number is 6 on UBI_IOC_MAGIC and nothing here occupies that slot. */

/* Control device ioctls (/dev/ubi_ctrl). */
#define UBI_IOCATT _IOW(UBI_CTRL_IOC_MAGIC, 64, struct ubi_attach_req)
#define UBI_IOCDET _IOW(UBI_CTRL_IOC_MAGIC, 65, __s32)

/* Volume device ioctls (/dev/ubiN_M). */
#define UBI_IOCVOLUP      _IOW(UBI_VOL_IOC_MAGIC, 0, __s64)
#define UBI_IOCEBER       _IOW(UBI_VOL_IOC_MAGIC, 1, __s32)
#define UBI_IOCEBCH       _IOW(UBI_VOL_IOC_MAGIC, 2, __s32)
#define UBI_IOCEBMAP      _IOW(UBI_VOL_IOC_MAGIC, 3, struct ubi_map_req)
#define UBI_IOCEBUNMAP    _IOW(UBI_VOL_IOC_MAGIC, 4, __s32)
#define UBI_IOCEBISMAP    _IOR(UBI_VOL_IOC_MAGIC, 5, __s32)
#define UBI_IOCSETVOLPROP _IOW(UBI_VOL_IOC_MAGIC, 6, \
                               struct ubi_set_vol_prop_req)
#define UBI_IOCVOLCRBLK   _IOW(UBI_VOL_IOC_MAGIC, 7, \
                               struct ubi_blkcreate_req)
#define UBI_IOCVOLRMBLK   _IO(UBI_VOL_IOC_MAGIC, 8)

#endif /* _CRTL_MTD_UBI_USER_H */
