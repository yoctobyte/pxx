/* SPDX-License-Identifier: Zlib */
/* The kernel UAPI that util-linux's libblkid and libfdisk use (zoned block
   devices, BLKPG, the OPAL lock status and libblkid's optical-drive
   requests), compared against GCC'S VIEW OF THE SAME SOURCE, the shape of
   c_crtl_uapi_constants.c: no expected value is written down, so nothing
   can go stale, and the two sides are compiled from different header trees.
   The numbers travel to the kernel, so a wrong one is a different request on
   the disk that was opened, not an error. The sizeof/offsetof rows are the
   layouts the kernel reads and writes through those requests. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stddef.h>
#include <limits.h>   /* the kernel cdrom.h spells CDSL_CURRENT as INT_MAX and leaves it to the includer */
#include <linux/ioctl.h>
#include <linux/blkzoned.h>
#include <linux/blkpg.h>
#include <linux/sed-opal.h>
#include <linux/cdrom.h>

#define P(x) printf("%-34s %ld\n", #x, (long)(x))
#define O(s, f) printf("%-34s %ld\n", "offsetof(" #s ", " #f ")", (long)offsetof(s, f))

int main(void)
{
  P(_IO(0x12, 1)); P(_IOR('p', 2, int)); P(_IOW(0x12, 3, long)); P(_IOWR(0x12, 4, char));

  P(BLK_ZONE_TYPE_CONVENTIONAL); P(BLK_ZONE_TYPE_SEQWRITE_REQ); P(BLK_ZONE_TYPE_SEQWRITE_PREF);
  P(BLK_ZONE_COND_NOT_WP); P(BLK_ZONE_COND_EMPTY); P(BLK_ZONE_COND_IMP_OPEN);
  P(BLK_ZONE_COND_EXP_OPEN); P(BLK_ZONE_COND_CLOSED); P(BLK_ZONE_COND_READONLY);
  P(BLK_ZONE_COND_FULL); P(BLK_ZONE_COND_OFFLINE); P(BLK_ZONE_REP_CAPACITY);
  P(BLKREPORTZONE); P(BLKRESETZONE); P(BLKGETZONESZ); P(BLKGETNRZONES);
  P(BLKOPENZONE); P(BLKCLOSEZONE); P(BLKFINISHZONE);
  P(sizeof(struct blk_zone)); O(struct blk_zone, wp); O(struct blk_zone, type);
  O(struct blk_zone, cond); O(struct blk_zone, reset); O(struct blk_zone, capacity);
  P(sizeof(struct blk_zone_report)); O(struct blk_zone_report, nr_zones);
  O(struct blk_zone_report, flags); O(struct blk_zone_report, zones);
  P(sizeof(struct blk_zone_range)); O(struct blk_zone_range, nr_sectors);

  P(BLKPG); P(BLKPG_ADD_PARTITION); P(BLKPG_DEL_PARTITION); P(BLKPG_RESIZE_PARTITION);
  P(BLKPG_DEVNAMELTH); P(BLKPG_VOLNAMELTH);
  P(sizeof(struct blkpg_ioctl_arg)); O(struct blkpg_ioctl_arg, datalen); O(struct blkpg_ioctl_arg, data);
  P(sizeof(struct blkpg_partition)); O(struct blkpg_partition, length); O(struct blkpg_partition, pno);
  O(struct blkpg_partition, devname); O(struct blkpg_partition, volname);

  P(OPAL_FL_SUPPORTED); P(OPAL_FL_LOCKING_SUPPORTED); P(OPAL_FL_LOCKING_ENABLED);
  P(OPAL_FL_LOCKED); P(OPAL_FL_MBR_ENABLED); P(OPAL_FL_MBR_DONE); P(OPAL_FL_SUM_SUPPORTED);
  P(IOC_OPAL_GET_STATUS); P(sizeof(struct opal_status));

  P(CDROMMULTISESSION); P(CDROM_GET_CAPABILITY); P(CDROM_LAST_WRITTEN);
  P(CDROM_LBA); P(CDROM_MSF); P(CDSL_NONE); P(CDSL_CURRENT);
  P(sizeof(struct cdrom_msf0)); P(sizeof(union cdrom_addr));
  P(sizeof(struct cdrom_multisession)); O(struct cdrom_multisession, xa_flag);
  O(struct cdrom_multisession, addr_format);
  return 0;
}
