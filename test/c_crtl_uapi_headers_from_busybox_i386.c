/* crtl: <linux/if.h>, <linux/if_arp.h>, <linux/if_vlan.h>, <linux/jffs2.h>,
 * <sys/vt.h>, <linux/if_bonding.h>, <linux/mii.h> and <linux/ethtool.h> --
 * EIGHT headers crtl did not have, all found by attempting busybox for i386 at
 * the 394-applet scope.
 *
 * WHY i386 FOUND THEM AND x86-64 DID NOT: the host-header fallback is
 * native-only. On x86-64 an unknown <h> resolves from /usr/include with a
 * warning and the TU compiles against GLIBC's copy; on any cross target the
 * search path has no /usr/include and it is a hard `include file not found'.
 * So these five were invisible on the target everybody builds on.
 * bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
 *
 * THE LAST TWO ARRIVED ONLY AFTER THE FIRST FIVE LANDED, and that is the
 * finding rather than a detail: a translation unit reports ONE missing include
 * and stops, so ifenslave.c could not ask for <linux/if_bonding.h> until
 * <linux/if.h> existed, and ifplugd.c could not ask for <linux/mii.h>. The
 * fallback had masked every layer at once on x86-64, so peeling one reveals
 * the next. Any count of missing headers taken from a single run is a LOWER
 * BOUND, never the list. <linux/ethtool.h> is the THIRD layer of that same
 * two-translation-unit peel and arrived after if_bonding.h and mii.h did.
 *
 * THE ethtool STRUCTS ARE IOCTL PAYLOADS, so the LAYOUT is the interface and
 * not merely the field names. A short ethtool_drvinfo is neither a compile
 * error nor a failure at the ioctl: the driver writes 196 bytes into whatever
 * the caller supplied, and a struct that ends early corrupts whatever busybox
 * put beside it. ifenslave WRITES driver[] and fw_version[] before the call --
 * it is how the bonding driver is told which ABI version is calling -- so that
 * struct travels in both directions and its offsets are load-bearing both ways.
 * The rows therefore assert offsets, not just sizes.
 *
 * EVERY VALUE HERE IS A KERNEL OR WIRE CONSTANT, so there is nothing to derive
 * them from and the host's own headers are the oracle. This file is diffed
 * against `gcc' -- which reads /usr/include -- so it is a real differential
 * rather than a restatement of what we wrote.
 *
 * ROW `jffs2' CARRIES THE PACKING CLAIM. struct jffs2_unknown_node is written
 * to FLASH as a clean marker by flash_eraseall, and every field is wrapped in
 * a one-member struct precisely so nobody assigns to it without byteswapping.
 * sizeof must be 12, not 16: an unpacked layout is not a compile error, it is
 * a filesystem the kernel mounts and then reports as garbage.
 *
 * ROW `vt' pins sizeof(struct vt_mode) at 8. VT_SETMODE hands it to the kernel
 * by pointer, so a wider struct is written past by the caller, not rejected.
 *
 * A first cut of <linux/if_vlan.h> also carried VLAN_HLEN, VLAN_ETH_ALEN,
 * VLAN_N_VID and struct vlan_hdr. Those are kernel-INTERNAL and appear in no
 * user-facing header, so there was no oracle for them and the values would
 * have been invented. gcc refusing this probe is what caught it; they are gone.
 */
#include <stdio.h>
#include <stddef.h>
#include <linux/if.h>
#include <linux/if_arp.h>
#include <linux/if_vlan.h>
#include <linux/jffs2.h>
#include <sys/vt.h>
#include <linux/sockios.h>
#include <linux/if_bonding.h>
#include <linux/mii.h>
#include <linux/ethtool.h>

int main(void)
{
	struct ifreq r;
	struct jffs2_unknown_node n;
	struct vt_mode m;

	printf("if      %d %x %x %x %x %d\n", IFNAMSIZ, IFF_UP, IFF_RUNNING,
	       IFF_MASTER, IFF_SLAVE, (int)sizeof r.ifr_name);
	printf("arphrd  %d %d %d %d %x %x\n", ARPHRD_NETROM, ARPHRD_ETHER,
	       ARPHRD_LOOPBACK, ARPHRD_PPP, ARPHRD_VOID, ARPHRD_NONE);
	printf("vlan    %x %x %x %x %x\n", VLAN_FLAG_REORDER_HDR, VLAN_FLAG_GVRP,
	       VLAN_FLAG_LOOSE_BINDING, VLAN_FLAG_MVRP, VLAN_FLAG_BRIDGE_BINDING);
	printf("jffs2   %x %x %x | %d %d %d\n", JFFS2_MAGIC_BITMASK,
	       JFFS2_NODETYPE_CLEANMARKER, JFFS2_NODETYPE_INODE,
	       (int)sizeof n, (int)sizeof(jint16_t), (int)sizeof(jint32_t));
	printf("vt      %x %x %d %d | %d\n", VT_GETMODE, VT_SETMODE, VT_PROCESS,
	       VT_ACKACQ, (int)sizeof m);
	printf("bond    %x %x %x %x %d %d | %d %d %d\n", BOND_ENSLAVE_OLD,
	       BOND_RELEASE_OLD, BOND_CHANGE_ACTIVE_OLD, BOND_CHECK_MII_STATUS,
	       BOND_ABI_VERSION, BOND_MODE_ALB,
	       (int)sizeof(ifbond), (int)sizeof(ifslave), (int)sizeof(struct ad_info));
	printf("bondoff %d %d %d %d\n", (int)offsetof(ifslave, slave_id),
	       (int)offsetof(ifslave, slave_name), (int)offsetof(ifslave, link),
	       (int)offsetof(ifslave, link_failure_count));
	printf("mii     %x %x %x %x %x | %x %x %x %x | %d %d\n", MII_BMCR, MII_BMSR,
	       MII_ADVERTISE, MII_LPA, MII_ESTATUS, BMSR_LSTATUS, BMCR_ISOLATE,
	       BMCR_ANENABLE, ADVERTISE_ALL, (int)sizeof(struct mii_ioctl_data),
	       (int)(sizeof(struct mii_ioctl_data) == 4 * sizeof(__u16)));
	printf("ethcmd  %x %x %x %x %x %x %x | %d\n", ETHTOOL_GSET, ETHTOOL_SSET,
	       ETHTOOL_GDRVINFO, ETHTOOL_GREGS, ETHTOOL_GLINK, ETHTOOL_GEEPROM,
	       ETHTOOL_GSTATS, ETHTOOL_BUSINFO_LEN);
	printf("ethval  %d %d %d\n", (int)sizeof(struct ethtool_value),
	       (int)offsetof(struct ethtool_value, cmd),
	       (int)offsetof(struct ethtool_value, data));
	printf("ethdrv  %d | %d %d %d %d %d %d | %d %d %d %d %d\n",
	       (int)sizeof(struct ethtool_drvinfo),
	       (int)offsetof(struct ethtool_drvinfo, driver),
	       (int)offsetof(struct ethtool_drvinfo, version),
	       (int)offsetof(struct ethtool_drvinfo, fw_version),
	       (int)offsetof(struct ethtool_drvinfo, bus_info),
	       (int)offsetof(struct ethtool_drvinfo, erom_version),
	       (int)offsetof(struct ethtool_drvinfo, reserved2),
	       (int)offsetof(struct ethtool_drvinfo, n_priv_flags),
	       (int)offsetof(struct ethtool_drvinfo, n_stats),
	       (int)offsetof(struct ethtool_drvinfo, testinfo_len),
	       (int)offsetof(struct ethtool_drvinfo, eedump_len),
	       (int)offsetof(struct ethtool_drvinfo, regdump_len));
	printf("ethcm   %d | %d %d %d %d\n", (int)sizeof(struct ethtool_cmd),
	       (int)offsetof(struct ethtool_cmd, speed),
	       (int)offsetof(struct ethtool_cmd, maxtxpkt),
	       (int)offsetof(struct ethtool_cmd, lp_advertising),
	       (int)offsetof(struct ethtool_cmd, reserved));
	return 0;
}
