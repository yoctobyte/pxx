/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/rtc.h> -- the RTC character device ioctls.
 *
 * Written for pxx from the kernel's documented ABI (the numbers are the ABI,
 * checked against a gcc build over the system header on x86-64 and i386);
 * only what userland tools reach. Without it a native x86-64 build silently
 * took the HOST's copy and every cross target failed to find one.
 * Found building toybox (feature-c-toybox-builds-with-pxx).
 */
#ifndef PXX_CRTL_LINUX_RTC_H
#define PXX_CRTL_LINUX_RTC_H 1

#include <sys/ioctl.h>

struct rtc_time {
  int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst;
};
struct rtc_wkalrm {
  unsigned char enabled;
  unsigned char pending;
  struct rtc_time time;
};

#define RTC_AIE_ON    _IO('p', 0x01)
#define RTC_AIE_OFF   _IO('p', 0x02)
#define RTC_UIE_ON    _IO('p', 0x03)
#define RTC_UIE_OFF   _IO('p', 0x04)
#define RTC_PIE_ON    _IO('p', 0x05)
#define RTC_PIE_OFF   _IO('p', 0x06)
#define RTC_ALM_SET   _IOW('p', 0x07, struct rtc_time)
#define RTC_ALM_READ  _IOR('p', 0x08, struct rtc_time)
#define RTC_RD_TIME   _IOR('p', 0x09, struct rtc_time)
#define RTC_SET_TIME  _IOW('p', 0x0a, struct rtc_time)
#define RTC_WKALM_SET _IOW('p', 0x0f, struct rtc_wkalrm)
#define RTC_WKALM_RD  _IOR('p', 0x10, struct rtc_wkalrm)

/* interrupt flags read back from the device */
#define RTC_IRQF 0x80
#define RTC_PF   0x40
#define RTC_AF   0x20
#define RTC_UF   0x10

#endif
