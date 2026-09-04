/* crtl: <mtd/mtd-user.h> + <mtd/mtd-abi.h>, <sys/timex.h>, <sys/kd.h> +
 * <linux/kd.h>, <linux/capability.h> -- all found attempting busybox for i386.
 *
 * ROW 1 IS A LAYOUT ROW, NOT A SIZE ROW. struct mtd_info_user is a __u8
 * followed by five __u32 and a __u64, so it is 32 bytes with three bytes of
 * padding after `type' and four before `padding' -- a transcription that
 * reordered the fields to "tidy" the holes still compiles and still fills
 * every field, and MEMGETINFO then reports a flash size read out of the
 * erasesize slot. flashcp writes that many bytes to a device that cannot be
 * un-written.
 *
 * ROW 2 CARRIES THE __kernel_loff_t CLAIM: MEMGETBADBLOCK's argument type is
 * inside the ioctl NUMBER via _IOW's size field, and __kernel_loff_t is 64
 * bits on EVERY architecture. Spelling it off_t produces a different request
 * on a 32-bit build; the kernel rejects it, and a caller that ignores the
 * error scans a chip and reports no bad blocks at all.
 *
 * ROW 4 is struct timex's SIZE, which is 208 because of eleven trailing
 * padding words. The kernel copies sizeof(struct timex) both ways, so dropping
 * them does not fail -- adjtimex succeeds and writes past the end of the
 * caller's struct. Row 5 has ADJ_OFFSET_SINGLESHOT at 0x8001, not 0x8000: it
 * carries ADJ_OFFSET's bit too, so the plausible value asks for nothing.
 * ROW 7 issues the call, and asserts the RETURN IS A CLOCK STATE: 0..5 are all
 * success, only -1 is an error, so `if (adjtimex(&t))' reports a failure
 * exactly when a leap second is pending.
 *
 * ROW 9 is the LED/flag pair: KDSETLED takes LED_SCR/LED_NUM/LED_CAP and
 * KDSKBLED takes K_SCROLLLOCK/K_NUMLOCK/K_CAPSLOCK, and both sets are 1/2/4 in
 * that order -- a value from the wrong one is always accepted and always does
 * the other thing.
 *
 * ROW 12 is the capability version dance. _LINUX_CAPABILITY_VERSION is pinned
 * to v1 upstream and _LINUX_CAPABILITY_U32S_3 is 2 (the suffix counts
 * INTERFACE versions, the value counts WORDS), so reading the digit off the
 * name gives 3 and works until the kernel's bound stops matching. ROW 14 runs
 * the negotiation busybox depends on: capget with a bogus version writes the
 * supported one back into the header AND returns -1/EINVAL. An implementation
 * that only returned the error would pass a "capget fails" check and hang
 * busybox's retry loop.
 *
 * All rows diffed against gcc.
 */
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>   /* row 16's loff_t; glibc puts it here under __USE_MISC */
#include <sys/ioctl.h>
#include <mtd/mtd-user.h>
#include <sys/timex.h>
#include <sys/kd.h>
#include <linux/capability.h>

/* glibc's <linux/capability.h> declares the constants and not the calls --
   libcap supplies them there. crtl declares them, so this is for the ORACLE. */
#ifndef _CRTL_LINUX_CAPABILITY_H
extern int capget(cap_user_header_t, cap_user_data_t);
#endif

int main(void)
{
  struct timex tx;
  struct __user_cap_header_struct h;
  struct __user_cap_data_struct d[2];
  int rc;

  printf("1 %d | %d %d %d %d %d %d\n", (int)sizeof(mtd_info_t),
         (int)offsetof(struct mtd_info_user, type),
         (int)offsetof(struct mtd_info_user, flags),
         (int)offsetof(struct mtd_info_user, size),
         (int)offsetof(struct mtd_info_user, erasesize),
         (int)offsetof(struct mtd_info_user, oobsize),
         (int)offsetof(struct mtd_info_user, padding));
  printf("2 %x %x %x %x %x\n", (unsigned)MEMGETINFO, (unsigned)MEMERASE,
         (unsigned)MEMGETBADBLOCK, (unsigned)MEMGETOOBSEL, (unsigned)MEMERASE64);
  printf("3 %d %d %d %d | %d %d %d\n", (int)sizeof(erase_info_t),
         (int)sizeof(nand_ecclayout_t), (int)sizeof(struct mtd_write_req),
         (int)sizeof(struct mtd_read_req),
         MTD_NANDFLASH, MTD_CAP_RAM, MTD_FILE_MODE_RAW);

  printf("4 %d | %d %d %d %d %d\n", (int)sizeof(struct timex),
         (int)offsetof(struct timex, offset), (int)offsetof(struct timex, status),
         (int)offsetof(struct timex, time), (int)offsetof(struct timex, shift),
         (int)offsetof(struct timex, tai));
  printf("5 %x %x %x %x %x\n", ADJ_OFFSET, ADJ_TICK, ADJ_OFFSET_SINGLESHOT,
         ADJ_OFFSET_SS_READ, MOD_CLKA);
  printf("6 %x %x %x %x | %d %d\n", STA_PLL, STA_UNSYNC, STA_NANO, STA_RONLY,
         TIME_ERROR, MAXTC);
  memset(&tx, 0, sizeof tx);
  tx.modes = 0;                     /* read-only */
  rc = adjtimex(&tx);
  printf("7 %d %d\n", rc >= TIME_OK && rc <= TIME_ERROR, tx.tick > 0);

  printf("8 %x %x %x %x %x\n", GIO_FONT, PIO_FONTX, PIO_UNIMAP, KDFONTOP, KDGKBMODE);
  printf("9 %d %d %d | %d %d %d\n", LED_SCR, LED_NUM, LED_CAP,
         K_SCROLLLOCK, K_NUMLOCK, K_CAPSLOCK);
  printf("10 %d %d %d %d | %d %d\n", KD_FONT_OP_SET, KD_FONT_OP_GET,
         KD_FONT_OP_SET_DEFAULT, KD_FONT_OP_COPY, K_XLATE, K_UNICODE);
  printf("11 %d %d %d | %d %d\n", (int)sizeof(struct console_font),
         (int)sizeof(struct console_font_op), (int)sizeof(struct unimapdesc),
         (int)sizeof(struct kbsentry), (int)offsetof(struct kbsentry, kb_string));

  printf("12 %x %x %x | %d %d %d | %x %d\n",
         _LINUX_CAPABILITY_VERSION_1, _LINUX_CAPABILITY_VERSION_2,
         _LINUX_CAPABILITY_VERSION_3, _LINUX_CAPABILITY_U32S_1,
         _LINUX_CAPABILITY_U32S_2, _LINUX_CAPABILITY_U32S_3,
         _LINUX_CAPABILITY_VERSION, _LINUX_CAPABILITY_U32S);
  printf("13 %d %d %d | %d %x | %d %x | %d %d\n",
         CAP_CHOWN, CAP_SYSLOG, CAP_LAST_CAP,
         CAP_TO_INDEX(CAP_SYS_ADMIN), CAP_TO_MASK(CAP_SYS_ADMIN),
         CAP_TO_INDEX(CAP_SYSLOG), CAP_TO_MASK(CAP_SYSLOG),
         cap_valid(CAP_LAST_CAP), cap_valid(CAP_LAST_CAP + 1));

  memset(&h, 0, sizeof h);
  memset(d, 0, sizeof d);
  h.version = 0xdeadbeef;
  h.pid = 0;
  errno = 0;
  rc = capget(&h, d);
  printf("14 %d %d\n", rc == -1 && errno == EINVAL,
         h.version == (unsigned)_LINUX_CAPABILITY_VERSION_3
         || h.version == (unsigned)_LINUX_CAPABILITY_VERSION_2);
  memset(d, 0, sizeof d);
  printf("15 %d %d %d %d\n", capget(&h, d),
         (int)sizeof(struct __user_cap_header_struct),
         (int)sizeof(struct __user_cap_data_struct),
         (int)sizeof(struct vfs_ns_cap_data));
  /* ROW 16 IS loff_t, ASSERTED AS A RELATION so it carries no per-target
     constant and prints `16 1 1' on every architecture. It is `long long'
     everywhere -- <linux/types.h>'s __kernel_loff_t already says so, and
     MEMGETBADBLOCK (row 2) encodes that width in its ioctl NUMBER, so an
     `off_t' spelling issues a different request on every ILP32 target.
     crtl had no loff_t at all until 2026-09-04; busybox's flash_eraseall.c
     and nandwrite.c both refused because of it, with two error shapes that
     named neither the type nor each other.

     ORACLE NOTE: glibc gates loff_t behind __USE_MISC, so diffing this row
     needs `gcc -D_GNU_SOURCE'. crtl defines it unconditionally, which is the
     accept-more direction and not a divergence anyone can observe: a program
     that does not use loff_t cannot tell. Measured both ways 2026-09-04 --
     gcc -D_GNU_SOURCE and pxx agree on all 16 rows. */
  printf("16 %d %d\n", (int)(sizeof(loff_t) == sizeof(long long)),
         (int)(sizeof(loff_t) == 8));
  return 0;
}
