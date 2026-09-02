/* crtl: <linux/loop.h> and <asm/unistd.h>, found attempting busybox for i386.
 *
 * THIS TEST EXISTS FOR ONE TYPE. __kernel_old_dev_t has THREE widths and its
 * name says nothing about which: `unsigned long' on x86-64, `unsigned short'
 * on i386, `unsigned int' for everyone falling through to asm-generic. It is
 * the pre-2.6 device number, and it survives only because `struct loop_info'
 * -- the 32-bit LOOP_GET_STATUS -- has two of them. Getting it wrong does not
 * fail: on x86-64 a 16-bit version moves lo_inode and everything after it, and
 * the ioctl fills a backing inode from the middle of the struct.
 *
 * SO ROWS 1 AND 2 MUST DIFFER BETWEEN THE TARGETS, and the i386 cross row in
 * the Makefile asserts exactly that -- 168/8/16/32/48 native against
 * 140/4/8/16/32 there. A row that matched on both would mean the per-target
 * arm had not been taken, which is the failure a same-answer cross row cannot
 * see. Rows 3-5 are the same on both by construction (all __u64/__u32), and
 * are here as the control: they say the divergence above is the dev_t and not
 * the whole struct being misread.
 *
 * ROW 6 IS THE SAME SHAPE FOR SYSCALL NUMBERS. SYS_ioprio_set is 251 on
 * x86-64 and 289 on i386, and __NR_write is 1 against 4 -- busybox's
 * util-linux/ionice.c includes <asm/unistd.h> and then calls syscall(),
 * so a forwarder that reached the wrong table would compile and call
 * something else entirely.
 *
 * TWO STATUS STRUCTS AND FOUR IOCTLS, AND THE PAIRS DO NOT INTERCHANGE:
 * LOOP_GET_STATUS takes loop_info, LOOP_GET_STATUS64 takes loop_info64, and
 * handing the kernel the long one with the short request does not fail --
 * everything the caller reads past lo_offset is stale stack. Row 1 printing
 * two different sizes is what makes that assertion checkable at all.
 *
 * All rows diffed against gcc (and, for the cross row, against gcc -m32).
 */
#include <stdio.h>
#include <stddef.h>
#include <linux/loop.h>
#include <asm/unistd.h>
#include <sys/syscall.h>

int main(void)
{
  printf("1 %d %d %d\n", (int)sizeof(struct loop_info),
         (int)sizeof(struct loop_info64), (int)sizeof(struct loop_config));
  printf("2 %d %d %d %d %d\n",
         (int)offsetof(struct loop_info, lo_number),
         (int)offsetof(struct loop_info, lo_device),
         (int)offsetof(struct loop_info, lo_inode),
         (int)offsetof(struct loop_info, lo_offset),
         (int)offsetof(struct loop_info, lo_name));
  printf("3 %d %d %d %d\n",
         (int)offsetof(struct loop_info64, lo_offset),
         (int)offsetof(struct loop_info64, lo_number),
         (int)offsetof(struct loop_info64, lo_file_name),
         (int)offsetof(struct loop_info64, lo_init));
  printf("4 %x %x %x %x %x %x\n", LOOP_SET_FD, LOOP_CLR_FD, LOOP_GET_STATUS,
         LOOP_GET_STATUS64, LOOP_CONFIGURE, LOOP_CTL_GET_FREE);
  printf("5 %d %d %d %d %d\n", LO_NAME_SIZE, LO_KEY_SIZE, LO_FLAGS_READ_ONLY,
         LO_FLAGS_AUTOCLEAR, LOOP_CONFIGURE_SETTABLE_FLAGS);
  printf("6 %d %d\n", __NR_write, (int)SYS_ioprio_set);
  return 0;
}
