/* SPDX-License-Identifier: Zlib */
/* The UAPI headers crtl grew for busybox, compared against GCC'S VIEW OF THE
   SAME SOURCE. Same shape as c_crtl_header_constants.c and for the same
   reason: no expected value is written down anywhere, so nothing here can go
   stale, and the two sides really are compiled from different header trees so
   the diff can fail.

   WHY THESE PARTICULAR NUMBERS NEED A GUARD. They are ioctl COMMANDS and
   device MAJORS, and both travel to the kernel. RAID_AUTORUN is built out of
   MD_MAJOR, so a wrong major is a different ioctl on whatever device was
   opened -- not a compile error and not a run-time error, just a different
   request. Writing this test found exactly that: CLUSTERED_DISK_NACK had been
   written as _IO(MD_MAJOR, 0x2c) from memory and the kernel says 0x35.

   THE STRUCT ROWS ARE HERE ON PURPOSE. RFKILL_EVENT_SIZE_V1 is
   sizeof(struct rfkill_event) rather than a literal, so comparing it compares
   the LAYOUT: without __attribute__((packed)) that struct is 8 bytes instead
   of 6, and busybox's rfkill.c loops on `full_read(...) == RFKILL_EVENT_SIZE_V1'
   -- so an unpacked struct makes the applet read nothing, print nothing and
   report no error. A value row is the only thing that sees it. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <linux/major.h>
#include <linux/random.h>
#include <linux/raid/md_u.h>
#include <linux/rfkill.h>

#define P(x) printf("%-30s %ld\n", #x, (long)(x))

int main(void)
{
  /* device majors -- <linux/major.h> */
  P(UNNAMED_MAJOR);
  P(MEM_MAJOR);
  P(RAMDISK_MAJOR);
  P(FLOPPY_MAJOR);
  P(PTY_MASTER_MAJOR);
  P(IDE0_MAJOR);
  P(PTY_SLAVE_MAJOR);
  P(TTY_MAJOR);
  P(TTYAUX_MAJOR);
  P(LP_MAJOR);
  P(VCS_MAJOR);
  P(LOOP_MAJOR);
  P(SCSI_DISK0_MAJOR);
  P(SCSI_TAPE_MAJOR);
  P(MD_MAJOR);
  P(MISC_MAJOR);
  P(SCSI_CDROM_MAJOR);
  P(XT_DISK_MAJOR);
  P(INPUT_MAJOR);
  P(SOUND_MAJOR);
  P(CDU31A_CDROM_MAJOR);
  P(JOYSTICK_MAJOR);
  P(GOLDSTAR_CDROM_MAJOR);
  P(OPTICS_CDROM_MAJOR);
  P(SANYO_CDROM_MAJOR);
  P(MITSUMI_X_CDROM_MAJOR);
  P(SCSI_GENERIC_MAJOR);
  P(IDE1_MAJOR);
  P(DIGICU_MAJOR);
  P(DIGI_MAJOR);
  P(MITSUMI_CDROM_MAJOR);
  P(CDU535_CDROM_MAJOR);
  P(MATSUSHITA_CDROM_MAJOR);
  P(MATSUSHITA_CDROM2_MAJOR);
  P(QIC117_TAPE_MAJOR);
  P(MATSUSHITA_CDROM3_MAJOR);
  P(MATSUSHITA_CDROM4_MAJOR);
  P(ACSI_MAJOR);
  P(AZTECH_CDROM_MAJOR);
  P(MTD_BLOCK_MAJOR);
  P(CM206_CDROM_MAJOR);
  P(IDE2_MAJOR);
  P(IDE3_MAJOR);
  P(Z8530_MAJOR);
  P(NETLINK_MAJOR);
  P(PS2ESDI_MAJOR);
  P(IDETAPE_MAJOR);
  P(Z2RAM_MAJOR);
  P(RISCOM8_NORMAL_MAJOR);
  P(RISCOM8_CALLOUT_MAJOR);
  P(MKISS_MAJOR);
  P(IDE4_MAJOR);
  P(IDE5_MAJOR);
  P(SCSI_DISK1_MAJOR);
  P(SCSI_DISK2_MAJOR);
  P(SCSI_DISK3_MAJOR);
  P(SCSI_DISK4_MAJOR);
  P(SCSI_DISK5_MAJOR);
  P(SCSI_DISK6_MAJOR);
  P(SCSI_DISK7_MAJOR);
  P(COMPAQ_SMART2_MAJOR);
  P(COMPAQ_SMART2_MAJOR1);
  P(COMPAQ_SMART2_MAJOR2);
  P(COMPAQ_SMART2_MAJOR3);
  P(COMPAQ_SMART2_MAJOR4);
  P(COMPAQ_SMART2_MAJOR5);
  P(COMPAQ_SMART2_MAJOR6);
  P(COMPAQ_SMART2_MAJOR7);
  P(SPECIALIX_NORMAL_MAJOR);
  P(SPECIALIX_CALLOUT_MAJOR);
  P(AURORA_MAJOR);
  P(SCSI_CHANGER_MAJOR);
  P(IDE6_MAJOR);
  P(IDE7_MAJOR);
  P(IDE8_MAJOR);
  P(MTD_CHAR_MAJOR);
  P(IDE9_MAJOR);
  P(DASD_MAJOR);
  P(MDISK_MAJOR);
  P(UBD_MAJOR);
  P(PP_MAJOR);
  P(JSFD_MAJOR);
  P(PHONE_MAJOR);
  P(COMPAQ_CISS_MAJOR);
  P(COMPAQ_CISS_MAJOR1);
  P(COMPAQ_CISS_MAJOR2);
  P(COMPAQ_CISS_MAJOR3);
  P(COMPAQ_CISS_MAJOR4);
  P(COMPAQ_CISS_MAJOR5);
  P(COMPAQ_CISS_MAJOR6);
  P(COMPAQ_CISS_MAJOR7);
  P(VIODASD_MAJOR);
  P(VIOCD_MAJOR);
  P(ATARAID_MAJOR);
  P(SCSI_DISK8_MAJOR);
  P(SCSI_DISK9_MAJOR);
  P(SCSI_DISK10_MAJOR);
  P(SCSI_DISK11_MAJOR);
  P(SCSI_DISK12_MAJOR);
  P(SCSI_DISK13_MAJOR);
  P(SCSI_DISK14_MAJOR);
  P(SCSI_DISK15_MAJOR);
  P(UNIX98_PTY_MASTER_MAJOR);
  P(UNIX98_PTY_MAJOR_COUNT);
  P(DRBD_MAJOR);
  P(RTF_MAJOR);
  P(RAW_MAJOR);
  P(USB_ACM_MAJOR);
  P(USB_ACM_AUX_MAJOR);
  P(USB_CHAR_MAJOR);
  P(MMC_BLOCK_MAJOR);
  P(MSR_MAJOR);
  P(CPUID_MAJOR);
  P(IBM_TTY3270_MAJOR);
  P(IBM_FS3270_MAJOR);
  P(VIOTAPE_MAJOR);
  P(BLOCK_EXT_MAJOR);

  /* /dev/random ioctls and getrandom flags -- <linux/random.h> */
  P(RNDGETENTCNT);
  P(RNDADDTOENTCNT);
  P(RNDGETPOOL);
  P(RNDADDENTROPY);
  P(RNDZAPENTCNT);
  P(RNDCLEARPOOL);
  P(RNDRESEEDCRNG);
  P(GRND_NONBLOCK);
  P(GRND_RANDOM);
  P(GRND_INSECURE);

  /* md RAID ioctls -- <linux/raid/md_u.h> */
  P(MD_MAJOR_VERSION);
  P(MD_MINOR_VERSION);
  P(MD_PATCHLEVEL_VERSION);
  P(RAID_AUTORUN);
  P(CLEAR_ARRAY);
  P(HOT_REMOVE_DISK);
  P(SET_DISK_INFO);
  P(WRITE_RAID_INFO);
  P(UNPROTECT_ARRAY);
  P(PROTECT_ARRAY);
  P(HOT_ADD_DISK);
  P(SET_DISK_FAULTY);
  P(HOT_GENERATE_ERROR);
  P(SET_BITMAP_FILE);
  P(STOP_ARRAY);
  P(STOP_ARRAY_RO);
  P(RESTART_ARRAY_RW);
  P(CLUSTERED_DISK_NACK);

  /* rfkill -- <linux/rfkill.h> */
  P(RFKILL_TYPE_ALL);
  P(RFKILL_TYPE_WLAN);
  P(RFKILL_TYPE_BLUETOOTH);
  P(RFKILL_TYPE_UWB);
  P(RFKILL_TYPE_WIMAX);
  P(RFKILL_TYPE_WWAN);
  P(RFKILL_TYPE_GPS);
  P(RFKILL_TYPE_FM);
  P(RFKILL_TYPE_NFC);
  P(NUM_RFKILL_TYPES);
  P(RFKILL_OP_ADD);
  P(RFKILL_OP_DEL);
  P(RFKILL_OP_CHANGE);
  P(RFKILL_OP_CHANGE_ALL);
  P(RFKILL_HARD_BLOCK_SIGNAL);
  P(RFKILL_HARD_BLOCK_NOT_OWNER);
  P(RFKILL_IOC_NOINPUT);
  P(RFKILL_IOCTL_NOINPUT);
  /* Layout, not a constant: see the note at the top. */
  printf("%-30s %ld\n", "sizeof(rfkill_event)", (long)sizeof(struct rfkill_event));
  printf("%-30s %ld\n", "sizeof(rand_pool_info)", (long)sizeof(struct rand_pool_info));
  return 0;
}
