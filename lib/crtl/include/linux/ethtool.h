/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_ETHTOOL_H
#define PXX_CRTL_LINUX_ETHTOOL_H 1

/* The SIOCETHTOOL sub-command numbers and the three structures busybox passes
   through ifreq's ifr_data.

   A DELIBERATE SUBSET, and the boundary is stated rather than implied: the
   kernel's own <linux/ethtool.h> is ~2500 lines of link-mode bitmaps, ring and
   coalesce parameters, RSS contexts and self-test descriptors, none of which
   any translation unit here names. What IS here is every ETHTOOL_G* number a
   busybox source mentions, its S* partner where one exists, and the three
   payload structs -- growing it further is a decision for a program that wants
   one, not for completeness.

   THE STRUCTS ARE IOCTL PAYLOADS, so their LAYOUT is the interface and not
   merely their field names. `struct ethtool_drvinfo' is 196 bytes; a shorter
   one means the driver writes past the caller's buffer, which is not a compile
   error and not a crash at the ioctl -- it is a corrupted stack frame in
   whatever busybox put next to it. The test asserts sizeof and offsets, not
   just that the fields exist.

   GENERATED FROM THE HOST'S <linux/ethtool.h>, which is the oracle. Note that
   networking/nameif.c does NOT use this header -- it carries its own private
   copy of ethtool_cmd and ETHTOOL_GSET -- so it neither needs this file nor
   conflicts with it.

   Found attempting busybox on i386: networking/ifenslave.c and ifplugd.c stop
   at this include, and only after <linux/if_bonding.h> and <linux/mii.h>
   landed. feature-c-corpus-busybox-i386-the-second-architecture */

#include <linux/types.h>

#define ETHTOOL_FWVERS_LEN     32
#define ETHTOOL_BUSINFO_LEN    32
#define ETHTOOL_EROMVERS_LEN   32

#define ETHTOOL_GSET           0x00000001   /* DEPRECATED, get settings */
#define ETHTOOL_SSET           0x00000002   /* DEPRECATED, set settings */
#define ETHTOOL_GDRVINFO       0x00000003   /* get driver info */
#define ETHTOOL_GREGS          0x00000004   /* get NIC registers */
#define ETHTOOL_GWOL           0x00000005
#define ETHTOOL_SWOL           0x00000006
#define ETHTOOL_GMSGLVL        0x00000007
#define ETHTOOL_SMSGLVL        0x00000008
#define ETHTOOL_NWAY_RST       0x00000009   /* restart autonegotiation */
#define ETHTOOL_GLINK          0x0000000a   /* get link status */
#define ETHTOOL_GEEPROM        0x0000000b   /* get EEPROM data */
#define ETHTOOL_SEEPROM        0x0000000c
#define ETHTOOL_GCOALESCE      0x0000000e
#define ETHTOOL_SCOALESCE      0x0000000f
#define ETHTOOL_GRINGPARAM     0x00000010
#define ETHTOOL_SRINGPARAM     0x00000011
#define ETHTOOL_GPAUSEPARAM    0x00000012
#define ETHTOOL_SPAUSEPARAM    0x00000013
#define ETHTOOL_GSTRINGS       0x0000001b
#define ETHTOOL_TEST           0x0000001a
#define ETHTOOL_PHYS_ID        0x0000001c
#define ETHTOOL_GSTATS         0x0000001d   /* get NIC-specific statistics */
#define ETHTOOL_GPERMADDR      0x00000020

/* SIOCETHTOOL's generic one-word answer: `cmd' in, `data' out. */
struct ethtool_value {
	__u32 cmd;
	__u32 data;
};

/* 196 bytes. ifenslave WRITES driver[] and fw_version[] before the ioctl --
   it is how the bonding driver is told which ABI version is calling -- so
   this one travels in both directions. */
struct ethtool_drvinfo {
	__u32 cmd;
	char  driver[32];
	char  version[32];
	char  fw_version[ETHTOOL_FWVERS_LEN];
	char  bus_info[ETHTOOL_BUSINFO_LEN];
	char  erom_version[ETHTOOL_EROMVERS_LEN];
	char  reserved2[12];
	__u32 n_priv_flags;
	__u32 n_stats;
	__u32 testinfo_len;
	__u32 eedump_len;
	__u32 regdump_len;
};

/* Deprecated in the kernel in favour of the link-mode bitmaps, and still what
   ETHTOOL_GSET returns. Kept because nameif.c's private copy is this exact
   shape, so a program that reaches for the header expects it here too. */
struct ethtool_cmd {
	__u32 cmd;
	__u32 supported;
	__u32 advertising;
	__u16 speed;
	__u8  duplex;
	__u8  port;
	__u8  phy_address;
	__u8  transceiver;
	__u8  autoneg;
	__u8  mdio_support;
	__u32 maxtxpkt;
	__u32 maxrxpkt;
	__u16 speed_hi;
	__u8  eth_tp_mdix;
	__u8  eth_tp_mdix_ctrl;
	__u32 lp_advertising;
	__u32 reserved[2];
};

#endif
