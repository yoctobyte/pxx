/* crtl: <linux/if_packet.h>, <linux/input.h> + <linux/input-event-codes.h>,
 * <linux/hdreg.h>, <linux/i2c.h> + <linux/i2c-dev.h>, <sys/mtio.h>,
 * <sys/statvfs.h> -- all found attempting busybox for i386.
 *
 * FIVE OF THESE ROWS MUST DIFFER BETWEEN THE TARGETS and the i386 cross row in
 * the Makefile asserts that they do -- rows 4, 11, 15, 16 and 17. struct
 * input_event is 24 bytes natively and 16 on i386, because it holds a struct
 * timeval; struct hd_geometry is 16 against 8, because `start' is `unsigned
 * long'; struct mtget is 48 against 28, which changes MTIOCGET's NUMBER
 * (0x80306d02 against 0x801c6d02) since the size is encoded in it; struct
 * statvfs is 112 against 72, because `int __f_unused' exists only on 32-bit.
 * A cross row that matched everywhere would mean no per-target arm had been
 * taken -- the failure a same-answer cross row cannot see. Every OTHER row is
 * byte-identical on both, and that is the control: it says the divergence is
 * these five types and not the whole file being read differently.
 *
 * ROW 1 IS THE TWO PACKET_* VOCABULARIES. PACKET_HOST..PACKET_OUTGOING are
 * sll_pkttype VALUES and PACKET_ADD_MEMBERSHIP onward are setsockopt OPTION
 * names, numbered from the same small integers: PACKET_MULTICAST is 2 and so
 * is PACKET_DROP_MEMBERSHIP, PACKET_OUTGOING is 4 and PACKET_RX_RING is 5. A
 * value from the wrong one is always a legal value of the other.
 *
 * ROW 5 IS THE OVERLAP THAT MAKES <linux/input-event-codes.h> DANGEROUS: code
 * 1 is KEY_ESC under EV_KEY, REL_Y under EV_REL, ABS_Y under EV_ABS and
 * SND_TONE under EV_SND. struct input_event carries type and code as two bare
 * __u16, so nothing separates them but the programmer.
 *
 * ROW 6 IS EVIOCGNAME AND EVIOCGBIT BUILDING THE IOCTL FROM A LENGTH. The size
 * is a field of the request, so the same call with a different sizeof is a
 * DIFFERENT ioctl and the kernel bounds its copy by the encoded length --
 * a stale constant truncates or overruns.
 *
 * ROW 11 IS hd_driveid AT 512 BYTES, the raw ATA IDENTIFY page read field by
 * field. A subset of it is not a smaller struct, it is one where every member
 * after the omission is at the wrong offset, and hdparm then prints a
 * plausible model string belonging to nothing.
 *
 * ROW 14 IS THE MTIOCTOP OP CODES, a flat 0..34 with no encoding to catch a
 * slip. MTERASE is 13 and MTRAS1 is 14, one apart, and one of them erases the
 * tape.
 *
 * ROW 17 RUNS statvfs("/") AND ROW 18 IS THE MASK THAT MAKES IT MATCH: glibc
 * strips ST_VALID from f_flag because it is statfs's internal "the kernel
 * filled this in" marker, not a mount option, and it sits at 0x0020 among the
 * real ones. Measured 2026-09-02, that mask was the ONLY place a
 * statfs-derived statvfs disagreed with glibc.
 *
 * All rows diffed against gcc, and the i386 row against gcc -m32.
 */
#include <stdio.h>
#include <stddef.h>
#include <linux/if_packet.h>
#include <linux/input.h>
#include <linux/hdreg.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#include <sys/mtio.h>
#include <sys/statvfs.h>

int main(void)
{
  struct statvfs v;
  int rc;

  printf("1 %d %d %d %d | %d %d %d %d\n", PACKET_HOST, PACKET_BROADCAST,
         PACKET_MULTICAST, PACKET_OUTGOING,
         PACKET_ADD_MEMBERSHIP, PACKET_DROP_MEMBERSHIP, PACKET_RX_RING,
         PACKET_AUXDATA);
  printf("2 %d | %d %d %d %d %d\n", (int)sizeof(struct tpacket_auxdata),
         (int)offsetof(struct tpacket_auxdata, tp_status),
         (int)offsetof(struct tpacket_auxdata, tp_snaplen),
         (int)offsetof(struct tpacket_auxdata, tp_mac),
         (int)offsetof(struct tpacket_auxdata, tp_vlan_tci),
         (int)offsetof(struct tpacket_auxdata, tp_vlan_tpid));
  printf("3 %d %d %x\n", (int)sizeof(struct sockaddr_pkt), TP_STATUS_VLAN_VALID,
         PACKET_FANOUT_FLAG_DEFRAG);

  printf("4 %d | %d %d %d %d\n", (int)sizeof(struct input_event),
         (int)offsetof(struct input_event, time),
         (int)offsetof(struct input_event, type),
         (int)offsetof(struct input_event, code),
         (int)offsetof(struct input_event, value));
  printf("5 %d %d %d %d %d | %d %d %d %d\n", EV_SYN, EV_KEY, EV_REL, EV_ABS, EV_SW,
         KEY_ESC, REL_Y, ABS_Y, SND_TONE);
  printf("6 %x %x %x %x\n", (unsigned)EVIOCGVERSION, (unsigned)EVIOCGID,
         (unsigned)EVIOCGNAME(64), (unsigned)EVIOCGBIT(EV_KEY, 96));
  printf("7 %d %d %d %d | %x\n", KEY_POWER, KEY_SLEEP, SW_LID, SW_RFKILL_ALL,
         EV_VERSION);
  printf("8 %d %d %d %d\n", (int)sizeof(struct input_id),
         (int)sizeof(struct input_absinfo),
         (int)sizeof(struct input_keymap_entry), (int)sizeof(struct input_mask));

  printf("9 %x %x %x %x %x\n", HDIO_GETGEO, HDIO_GET_IDENTITY, HDIO_GET_MULTCOUNT,
         HDIO_DRIVE_CMD, HDIO_DRIVE_RESET);
  printf("10 %x %x %x %x | %x %x\n", HDIO_SET_MULTCOUNT, HDIO_SET_DMA,
         HDIO_SET_BUSSTATE, HDIO_GET_BUSSTATE, WIN_IDENTIFY, WIN_SETFEATURES);
  printf("11 %d %d | %d %d %d\n", (int)sizeof(struct hd_driveid),
         (int)sizeof(struct hd_geometry),
         (int)offsetof(struct hd_driveid, serial_no),
         (int)offsetof(struct hd_driveid, model),
         (int)offsetof(struct hd_driveid, command_set_1));

  printf("12 %x %x %x %x %x %x %x\n", I2C_RETRIES, I2C_TIMEOUT, I2C_SLAVE,
         I2C_SLAVE_FORCE, I2C_FUNCS, I2C_RDWR, I2C_SMBUS);
  printf("13 %d %d | %x %x %x | %x %x\n", I2C_SMBUS_READ, I2C_SMBUS_WRITE,
         I2C_M_RD, I2C_M_TEN, I2C_M_RECV_LEN,
         I2C_FUNC_I2C, I2C_FUNC_SMBUS_READ_BLOCK_DATA);

  printf("14 %d %d %d %d %d %d | %d %d\n", MTRESET, MTFSF, MTWEOF, MTEOM,
         MTERASE, MTRAS1, MTSETBLK, MTMKPART);
  printf("15 %d %d %d %d\n", (int)sizeof(struct mtop), (int)sizeof(struct mtget),
         (int)sizeof(struct mtpos), (int)sizeof(struct mtconfiginfo));
  printf("16 %x %x %x | %s\n", (unsigned)MTIOCTOP, (unsigned)MTIOCGET,
         (unsigned)MTIOCPOS, DEFTAPE);

  printf("17 %d | %d %d %d %d\n", (int)sizeof(struct statvfs),
         (int)offsetof(struct statvfs, f_blocks),
         (int)offsetof(struct statvfs, f_fsid),
         (int)offsetof(struct statvfs, f_flag),
         (int)offsetof(struct statvfs, f_namemax));
  rc = statvfs("/", &v);
  printf("18 %d %lu %lu %d %d %d\n", rc, (unsigned long)v.f_bsize,
         (unsigned long)v.f_namemax, v.f_blocks > 0, v.f_favail == v.f_ffree,
         (int)((v.f_flag & 0x0020) != 0));   /* ST_VALID must NOT survive */
  return 0;
}
