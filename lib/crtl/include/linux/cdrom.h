/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/cdrom.h> -- CD-ROM drive ioctls and drive status codes.
 *
 * The kernel's ABI numbers, checked against a gcc build over the system
 * header; only the commands userland tools send. Found building toybox's
 * eject (feature-c-toybox-builds-with-pxx).
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

#define CDS_NO_INFO         0
#define CDS_NO_DISC         1
#define CDS_TRAY_OPEN       2
#define CDS_DRIVE_NOT_READY 3
#define CDS_DISC_OK         4

#endif
