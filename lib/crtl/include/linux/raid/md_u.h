/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_RAID_MD_U_H
#define PXX_CRTL_LINUX_RAID_MD_U_H 1

/* <linux/raid/md_u.h> -- the md (software RAID) ioctl commands.

   ONLY THE IOCTL COMMANDS, and deliberately: the kernel's copy also carries
   mdu_array_info_t, mdu_disk_info_t and friends, which are structures that
   travel to the kernel and are versioned by MD_MAJOR_VERSION. Nothing in this
   tree passes one -- busybox's miscutils/raidautorun.c calls exactly
   `xioctl(fd, RAID_AUTORUN, NULL)' -- and a struct copied without a consumer
   is a wire layout with no test behind it. Add one when something needs it,
   with a layout probe, the way <sys/statfs.h> records its own.

   RAID_AUTORUN'S NUMBER IS BUILT FROM MD_MAJOR, so <linux/major.h> is a real
   dependency and not a convenience: get the major wrong and this is a
   different ioctl issued on whatever was opened. That is the class of failure
   this whole header set exists to avoid -- it does not refuse, it acts.

   Found attempting busybox on i386, as raidautorun.c's SECOND blocker: the
   first was <linux/major.h>, and this one was invisible until that was
   supplied. */

#include <linux/major.h>
#include <sys/ioctl.h>

#define MD_MAJOR_VERSION        0
#define MD_MINOR_VERSION       90
#define MD_PATCHLEVEL_VERSION   3

/* THE COMMANDS THAT NEED NO STRUCT. Every md ioctl whose argument is one of
   the mdu_* types is deliberately absent, because those types are absent: a
   macro spelled _IOR(MD_MAJOR, 0x11, mdu_array_info_t) would compile in this
   file and fail at its first USE, naming a type nobody can find. An absent
   command name is a compile error that says what is missing; a present one
   that cannot be expanded is a compile error that says something else. The
   missing set is RAID_VERSION, GET_ARRAY_INFO, GET_DISK_INFO, GET_BITMAP_FILE,
   ADD_NEW_DISK, SET_ARRAY_INFO and RUN_ARRAY -- add the struct and the command
   together, with a layout probe, or neither. */
#define RAID_AUTORUN            _IO  (MD_MAJOR, 0x14)

#define CLEAR_ARRAY             _IO  (MD_MAJOR, 0x20)
#define HOT_REMOVE_DISK         _IO  (MD_MAJOR, 0x22)
#define SET_DISK_INFO           _IO  (MD_MAJOR, 0x24)
#define WRITE_RAID_INFO         _IO  (MD_MAJOR, 0x25)
#define UNPROTECT_ARRAY         _IO  (MD_MAJOR, 0x26)
#define PROTECT_ARRAY           _IO  (MD_MAJOR, 0x27)
#define HOT_ADD_DISK            _IO  (MD_MAJOR, 0x28)
#define SET_DISK_FAULTY         _IO  (MD_MAJOR, 0x29)
#define HOT_GENERATE_ERROR      _IO  (MD_MAJOR, 0x2a)
#define SET_BITMAP_FILE         _IOW (MD_MAJOR, 0x2b, int)

#define STOP_ARRAY              _IO  (MD_MAJOR, 0x32)
#define STOP_ARRAY_RO           _IO  (MD_MAJOR, 0x33)
#define RESTART_ARRAY_RW        _IO  (MD_MAJOR, 0x34)
#define CLUSTERED_DISK_NACK     _IO  (MD_MAJOR, 0x35)

#endif /* PXX_CRTL_LINUX_RAID_MD_U_H */
