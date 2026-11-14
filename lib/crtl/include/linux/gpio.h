/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/gpio.h> -- the GPIO character device, ABI v1 only (what toybox's gpiod uses); the v2 line API is absent.
 *
 * Written for pxx from the kernel's documented ABI (the numbers are the ABI,
 * checked against a gcc build over the system header on x86-64 and i386);
 * only what userland tools reach. Without it a native x86-64 build silently
 * took the HOST's copy and every cross target failed to find one.
 * Found building toybox (feature-c-toybox-builds-with-pxx).
 */
#ifndef PXX_CRTL_LINUX_GPIO_H
#define PXX_CRTL_LINUX_GPIO_H 1

#include <sys/ioctl.h>
#include <linux/types.h>

#define GPIO_MAX_NAME_SIZE 32
#define GPIOHANDLES_MAX    64

struct gpiochip_info {
  char name[GPIO_MAX_NAME_SIZE];
  char label[GPIO_MAX_NAME_SIZE];
  __u32 lines;
};

#define GPIOLINE_FLAG_KERNEL      (1UL << 0)
#define GPIOLINE_FLAG_IS_OUT      (1UL << 1)
#define GPIOLINE_FLAG_ACTIVE_LOW  (1UL << 2)
#define GPIOLINE_FLAG_OPEN_DRAIN  (1UL << 3)
#define GPIOLINE_FLAG_OPEN_SOURCE (1UL << 4)

struct gpioline_info {
  __u32 line_offset;
  __u32 flags;
  char name[GPIO_MAX_NAME_SIZE];
  char consumer[GPIO_MAX_NAME_SIZE];
};

#define GPIOHANDLE_REQUEST_INPUT       (1UL << 0)
#define GPIOHANDLE_REQUEST_OUTPUT      (1UL << 1)
#define GPIOHANDLE_REQUEST_ACTIVE_LOW  (1UL << 2)
#define GPIOHANDLE_REQUEST_OPEN_DRAIN  (1UL << 3)
#define GPIOHANDLE_REQUEST_OPEN_SOURCE (1UL << 4)

struct gpiohandle_request {
  __u32 lineoffsets[GPIOHANDLES_MAX];
  __u32 flags;
  __u8 default_values[GPIOHANDLES_MAX];
  char consumer_label[GPIO_MAX_NAME_SIZE];
  __u32 lines;
  int fd;
};

struct gpiohandle_data {
  __u8 values[GPIOHANDLES_MAX];
};

#define GPIO_GET_CHIPINFO_IOCTL          _IOR(0xB4, 0x01, struct gpiochip_info)
#define GPIO_GET_LINEINFO_IOCTL          _IOWR(0xB4, 0x02, struct gpioline_info)
#define GPIO_GET_LINEHANDLE_IOCTL        _IOWR(0xB4, 0x03, struct gpiohandle_request)
#define GPIOHANDLE_GET_LINE_VALUES_IOCTL _IOWR(0xB4, 0x08, struct gpiohandle_data)
#define GPIOHANDLE_SET_LINE_VALUES_IOCTL _IOWR(0xB4, 0x09, struct gpiohandle_data)

#endif
