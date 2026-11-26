/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/cdrom.h> -- CD-ROM drive ioctls and drive status codes.
 *
 * The kernel's ABI numbers, checked against a gcc build over the system
 * header; only the commands userland tools send. Found building toybox's
 * eject (feature-c-toybox-builds-with-pxx); libblkid's optical-drive probe
 * added the capability, last-written and multisession requests.
 */
#ifndef PXX_CRTL_LINUX_CDROM_H
#define PXX_CRTL_LINUX_CDROM_H 1

#define CDROMPAUSE          0x5301
#define CDROMRESUME         0x5302
#define CDROMSTOP           0x5307
#define CDROMSTART          0x5308
#define CDROMEJECT          0x5309
#define CDROMEJECT_SW       0x530f
#define CDROMRESET          0x5312
#define CDROMCLOSETRAY      0x5319
#define CDROM_SET_OPTIONS   0x5320
#define CDROM_CLEAR_OPTIONS 0x5321
#define CDROM_SELECT_SPEED  0x5322
#define CDROM_MEDIA_CHANGED 0x5325
#define CDROM_DRIVE_STATUS  0x5326
#define CDROM_DISC_STATUS   0x5327
#define CDROM_LOCKDOOR      0x5329
/* what libblkid's probe asks of an optical drive (util-linux): is it one,
   is there a disc, where does its last session start */
#define CDROMMULTISESSION   0x5310
#define CDROM_GET_CAPABILITY 0x5331
#define CDROM_LAST_WRITTEN  0x5395

/* the address format a request asks for */
#define CDROM_LBA           0x01
#define CDROM_MSF           0x02

/* CDROM_DRIVE_STATUS's argument: the slot of a changer, or these two */
#define CDSL_NONE           (0x7fffffff - 1)
#define CDSL_CURRENT        0x7fffffff

#define CDS_NO_INFO         0
#define CDS_NO_DISC         1
#define CDS_TRAY_OPEN       2
#define CDS_DRIVE_NOT_READY 3
#define CDS_DISC_OK         4

struct cdrom_msf0 {
  unsigned char minute;
  unsigned char second;
  unsigned char frame;
};

union cdrom_addr {
  struct cdrom_msf0 msf;
  int lba;
};

/* CDROMMULTISESSION: where the last session starts, for an XA disc */
struct cdrom_multisession {
  union cdrom_addr addr;
  unsigned char xa_flag;
  unsigned char addr_format;
};

#endif
