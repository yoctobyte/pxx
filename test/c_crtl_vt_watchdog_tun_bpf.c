/* crtl: <linux/version.h>, <linux/sockios.h>, <linux/vt.h>,
 * <linux/watchdog.h>, <linux/if_tun.h>, <linux/filter.h>,
 * <linux/bpf_common.h> -- all found attempting busybox for i386.
 *
 * LINUX_VERSION_CODE ITSELF IS NOT DIFFABLE and row 2 is the weak one here:
 * the code describes the HEADERS, so gcc answers for whatever kernel-headers
 * package this box has and crtl answers a fixed claim about its own tree --
 * both are above busybox's thresholds, so both print 1 and the row would pass
 * for two different reasons. It is kept because a MISSING or mis-shaped
 * LINUX_VERSION_CODE fails it, which is the failure that reaches busybox.
 * Row 1 is a real oracle row: KERNEL_VERSION's packing is the same arithmetic
 * on both sides, and it includes the (c) > 255 clamp that stops a long stable
 * train from wrapping into the next minor.
 *
 * ROW 4 IS THE ONE THAT PAYS. Every value in <linux/bpf_common.h> is zero in
 * some field: BPF_LD, BPF_W, BPF_IMM, BPF_ADD, BPF_JA and BPF_K are all 0x00
 * and BPF_LDX, BPF_H and BPF_X are all 0x08. They are values of DIFFERENT
 * bitfields in one 16-bit opcode, so a name copied from the wrong group
 * assembles a LEGAL instruction with another meaning -- BPF_JGT for BPF_JGE
 * loses exactly the boundary packet. The row builds udhcp's real filter prologue
 * and prints the opcodes, which is the only way a transposition shows up.
 *
 * ROW 6 is struct sock_fprog's LAYOUT: `len' is `unsigned short', not int, and
 * setsockopt hands the whole struct to the kernel -- a widened field puts
 * `filter' at the wrong offset and the kernel reads a program from whatever
 * follows it.
 *
 * ROW 7 is struct vt_stat, whose v_state is SIXTEEN bits and is why VT_GETSTATE
 * cannot see past console 15. Row 8 is the watchdog pair whose DIRECTION bits
 * are part of the number: SETTIMEOUT is _IOWR and GETTIMEOUT is _IOR, so a
 * SETTIMEOUT written as _IOR is an ioctl the driver does not implement and the
 * daemon then runs on the hardware default while reporting it set one.
 *
 * ROW 10 is IFF_TUN's collision with <net/if.h>: IFF_NO_PI and IFF_MULTICAST
 * are the same bit in the same struct field, and only the ioctl says which
 * vocabulary is in force. Printing both is the point.
 *
 * Rows 1 and 3-10 diffed against gcc; row 2 as qualified above.
 */
#include <stdio.h>
#include <stddef.h>
#include <linux/version.h>
#include <linux/sockios.h>
#include <linux/vt.h>
#include <linux/watchdog.h>
#include <linux/filter.h>
#include <linux/if_tun.h>
#include <net/if.h>

static struct sock_filter prog[] = {
  BPF_STMT(BPF_LD | BPF_B | BPF_ABS, 9),                 /* load ip proto  */
  BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 17, 0, 6),         /* is it UDP?     */
  BPF_STMT(BPF_LD | BPF_H | BPF_ABS, 6),                 /* load frag bits */
  BPF_JUMP(BPF_JMP | BPF_JSET | BPF_K, 0x1fff, 4, 0),    /* fragmented?    */
  BPF_STMT(BPF_LDX | BPF_B | BPF_MSH, 0),                /* x = ip hdr len */
  BPF_STMT(BPF_LD | BPF_H | BPF_IND, 2),                 /* load dport     */
  BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 68, 0, 1),         /* is it 68?      */
  BPF_STMT(BPF_RET | BPF_K, 0x0fffffff),                 /* accept         */
  BPF_STMT(BPF_RET | BPF_K, 0),                          /* drop           */
};

int main(void)
{
  int i;

  printf("1 %d %d %d\n", KERNEL_VERSION(2, 6, 19), KERNEL_VERSION(6, 1, 0),
         KERNEL_VERSION(5, 4, 300));
  printf("2 %d %d\n", LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 0),
         LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 19));

  /* <linux/sockios.h> must agree with <sys/ioctl.h> -- one definition site. */
  printf("3 %x %x %x %x\n", SIOCBRADDBR, SIOCBRDELIF, SIOCBONDENSLAVE,
         SIOCDEVPRIVATE);

  printf("4");
  for (i = 0; i < (int)(sizeof prog / sizeof prog[0]); i++)
    printf(" %x", prog[i].code);
  printf("\n");
  printf("5 %d %d %d %d\n", prog[1].jf, prog[3].jt, (int)prog[7].k,
         (int)prog[0].k);

  printf("6 %d %d %d | %d %d %d %d\n",
         (int)sizeof(struct sock_fprog), (int)offsetof(struct sock_fprog, len),
         (int)offsetof(struct sock_fprog, filter),
         (int)sizeof(struct sock_filter), (int)offsetof(struct sock_filter, code),
         (int)offsetof(struct sock_filter, jt), (int)offsetof(struct sock_filter, k));

  printf("7 %d | %d %d %d | %x %x %x\n", (int)sizeof(struct vt_stat),
         (int)offsetof(struct vt_stat, v_active),
         (int)offsetof(struct vt_stat, v_signal),
         (int)offsetof(struct vt_stat, v_state),
         VT_OPENQRY, VT_GETSTATE, VT_DISALLOCATE);

  printf("8 %x %x %x %x\n", (unsigned)WDIOC_SETTIMEOUT, (unsigned)WDIOC_GETTIMEOUT,
         (unsigned)WDIOC_SETOPTIONS, (unsigned)WDIOC_GETSUPPORT);
  printf("9 %d %d %d\n", WDIOS_ENABLECARD, WDIOS_DISABLECARD, WDIOF_MAGICCLOSE);

  printf("10 %x %x %x %x | %x %x\n", IFF_TUN, IFF_TAP, IFF_NO_PI, IFF_PERSIST,
         (unsigned)TUNSETIFF, (unsigned)TUNSETPERSIST);
  return 0;
}
