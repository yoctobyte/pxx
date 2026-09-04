/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_RFKILL_H
#define PXX_CRTL_LINUX_RFKILL_H 1

/* <linux/rfkill.h> -- the /dev/rfkill event record and its enums.

   THE STRUCT IS THE WIRE FORMAT OF A CHARACTER DEVICE, so it is PACKED and its
   size is load-bearing in a way that is easy to miss: busybox's
   miscutils/rfkill.c loops on
   `full_read(fd, &event, sizeof(event)) == RFKILL_EVENT_SIZE_V1', so a struct
   one byte larger than the kernel's makes every read compare unequal and the
   applet reports nothing at all -- no error, no output. Without __attribute__
   ((packed)) this struct is 8 bytes rather than 6 on every target we build
   for, which is exactly that failure.

   RFKILL_EVENT_SIZE_V1 IS sizeof(struct rfkill_event) AND NOT A LITERAL, which
   is the kernel's own spelling and the right one: it makes the constant and
   the layout impossible to disagree. The kernel's comment explains why the
   struct was frozen at this version -- userspace treated short reads and
   writes as errors -- and the extended record lives in a separate type, so
   this one must never grow.

   struct rfkill_event_ext is NOT here: nothing in this tree opts into it, and
   the kernel's own documentation says a caller must accept short reads and
   writes before using it. A wire layout with no consumer has no test behind it.

   Found attempting busybox on i386, where there is no host header to fall back
   on. */

#include <stdint.h>
#include <sys/ioctl.h>

enum rfkill_type {
  RFKILL_TYPE_ALL = 0,
  RFKILL_TYPE_WLAN,
  RFKILL_TYPE_BLUETOOTH,
  RFKILL_TYPE_UWB,
  RFKILL_TYPE_WIMAX,
  RFKILL_TYPE_WWAN,
  RFKILL_TYPE_GPS,
  RFKILL_TYPE_FM,
  RFKILL_TYPE_NFC,
  NUM_RFKILL_TYPES
};

enum rfkill_operation {
  RFKILL_OP_ADD = 0,
  RFKILL_OP_DEL,
  RFKILL_OP_CHANGE,      /* one device, named by idx */
  RFKILL_OP_CHANGE_ALL   /* every device of a type, and the default for new ones */
};

enum rfkill_hard_block_reasons {
  RFKILL_HARD_BLOCK_SIGNAL   = 1 << 0,
  RFKILL_HARD_BLOCK_NOT_OWNER = 1 << 1
};

struct rfkill_event {
  uint32_t idx;
  uint8_t  type;
  uint8_t  op;
  uint8_t  soft;
  uint8_t  hard;
} __attribute__((packed));

#define RFKILL_EVENT_SIZE_V1  sizeof(struct rfkill_event)

/* Turn off rfkill-input, if the kernel has it. */
#define RFKILL_IOC_MAGIC      'R'
#define RFKILL_IOC_NOINPUT    1
#define RFKILL_IOCTL_NOINPUT  _IO(RFKILL_IOC_MAGIC, RFKILL_IOC_NOINPUT)

#endif /* PXX_CRTL_LINUX_RFKILL_H */
