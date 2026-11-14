/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <scsi/sg.h> -- the SCSI generic SG_IO interface.
 *
 * Written for pxx from the kernel's documented ABI (the numbers are the ABI,
 * checked against a gcc build over the system header on x86-64 and i386);
 * only what userland tools reach. Without it a native x86-64 build silently
 * took the HOST's copy and every cross target failed to find one.
 * Found building toybox (feature-c-toybox-builds-with-pxx).
 */
#ifndef PXX_CRTL_SCSI_SG_H
#define PXX_CRTL_SCSI_SG_H 1

typedef struct sg_io_hdr {
  int interface_id;            /* 'S' */
  int dxfer_direction;         /* SG_DXFER_* */
  unsigned char cmd_len;
  unsigned char mx_sb_len;
  unsigned short iovec_count;
  unsigned int dxfer_len;
  void *dxferp;
  unsigned char *cmdp;
  void *sbp;
  unsigned int timeout;        /* milliseconds */
  unsigned int flags;
  int pack_id;
  void *usr_ptr;
  unsigned char status;
  unsigned char masked_status;
  unsigned char msg_status;
  unsigned char sb_len_wr;
  unsigned short host_status;
  unsigned short driver_status;
  int resid;
  unsigned int duration;
  unsigned int info;
} sg_io_hdr_t;

#define SG_DXFER_NONE        (-1)
#define SG_DXFER_TO_DEV      (-2)
#define SG_DXFER_FROM_DEV    (-3)
#define SG_DXFER_TO_FROM_DEV (-4)

#define SG_INFO_OK_MASK 0x1
#define SG_INFO_OK      0x0

#define SG_IO               0x2285
#define SG_GET_VERSION_NUM  0x2282

#endif
