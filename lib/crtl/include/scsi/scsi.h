/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <scsi/scsi.h> -- SCSI command opcodes.
 *
 * The kernel's ABI numbers, checked against a gcc build over the system
 * header; only the commands userland tools send. Found building toybox's
 * eject (feature-c-toybox-builds-with-pxx).
 */
#ifndef PXX_CRTL_SCSI_SCSI_H
#define PXX_CRTL_SCSI_SCSI_H 1

#define TEST_UNIT_READY       0x00
#define REQUEST_SENSE         0x03
#define INQUIRY               0x12
#define MODE_SENSE            0x1a
#define START_STOP            0x1b
#define ALLOW_MEDIUM_REMOVAL  0x1e
#define READ_CAPACITY         0x25
#define READ_10               0x28
#define WRITE_10              0x2a
#define SYNCHRONIZE_CACHE     0x35

#endif
