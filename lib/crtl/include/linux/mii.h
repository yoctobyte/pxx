/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_MII_H
#define PXX_CRTL_LINUX_MII_H 1

/* The MII/PHY register numbers and their bits.

   THESE ARE REGISTER ADDRESSES ON A WIRE, not a kernel structure: MII_BMSR is
   register 1 on every 802.3 clause-22 PHY ever made, so unlike most of the
   linux/ UAPI headers nothing here varies by target, by kernel version, or
   by word size. That also means a wrong value cannot be caught by a size
   assertion -- SIOCGMIIREG will happily read register 2 and hand back a
   plausible 16-bit number that busybox's ifplugd then reports as a link
   state.

   GENERATED FROM THE HOST'S <linux/mii.h>, which is the oracle, and kept in
   that header's order so a diff against it reads straight down. The kernel's
   per-constant comments are not reproduced; the names carry the same
   information and the values are the part that has to match.

   THE KERNEL'S COPY ALSO CARRIES ~10 `static inline' HELPERS (mii_nway_result,
   ethtool_adv_to_mii_adv_t and friends) AND THEY ARE THE ONLY REASON ITS FIRST
   LINE IS `#include <linux/ethtool.h>'. They are omitted here: crtl has no
   <linux/ethtool.h>, no busybox translation unit calls one, and pulling a
   whole header in to satisfy an inline nobody invokes is how a shadow tree
   grows without anyone deciding to grow it. Add them WITH ethtool.h when a
   real program wants one -- not before.

   Found attempting busybox on i386: networking/ifplugd.c stops at this
   include, and only after <linux/if.h> landed -- a translation unit reports
   one missing include at a time.
   feature-c-corpus-busybox-i386-the-second-architecture */

#include <linux/types.h>

/* Generic MII registers */
#define MII_BMCR                 0x00
#define MII_BMSR                 0x01
#define MII_PHYSID1              0x02
#define MII_PHYSID2              0x03
#define MII_ADVERTISE            0x04
#define MII_LPA                  0x05
#define MII_EXPANSION            0x06
#define MII_CTRL1000             0x09
#define MII_STAT1000             0x0a
#define MII_MMD_CTRL             0x0d
#define MII_MMD_DATA             0x0e
#define MII_ESTATUS              0x0f
#define MII_DCOUNTER             0x12
#define MII_FCSCOUNTER           0x13
#define MII_NWAYTEST             0x14
#define MII_RERRCOUNTER          0x15
#define MII_SREVISION            0x16
#define MII_RESV1                0x17
#define MII_LBRERROR             0x18
#define MII_PHYADDR              0x19
#define MII_RESV2                0x1a
#define MII_TPISTATUS            0x1b
#define MII_NCONFIG              0x1c

/* Basic mode control register (MII_BMCR) */
#define BMCR_RESV                0x003f
#define BMCR_SPEED1000           0x0040
#define BMCR_CTST                0x0080
#define BMCR_FULLDPLX            0x0100
#define BMCR_ANRESTART           0x0200
#define BMCR_ISOLATE             0x0400
#define BMCR_PDOWN               0x0800
#define BMCR_ANENABLE            0x1000
#define BMCR_SPEED100            0x2000
#define BMCR_LOOPBACK            0x4000
#define BMCR_RESET               0x8000
#define BMCR_SPEED10             0x0000

/* Basic mode status register (MII_BMSR) */
#define BMSR_ERCAP               0x0001
#define BMSR_JCD                 0x0002
#define BMSR_LSTATUS             0x0004
#define BMSR_ANEGCAPABLE         0x0008
#define BMSR_RFAULT              0x0010
#define BMSR_ANEGCOMPLETE        0x0020
#define BMSR_RESV                0x00c0
#define BMSR_ESTATEN             0x0100
#define BMSR_100HALF2            0x0200
#define BMSR_100FULL2            0x0400
#define BMSR_10HALF              0x0800
#define BMSR_10FULL              0x1000
#define BMSR_100HALF             0x2000
#define BMSR_100FULL             0x4000
#define BMSR_100BASE4            0x8000

/* Advertisement control register (MII_ADVERTISE) */
#define ADVERTISE_SLCT           0x001f
#define ADVERTISE_CSMA           0x0001
#define ADVERTISE_10HALF         0x0020
#define ADVERTISE_1000XFULL      0x0020
#define ADVERTISE_10FULL         0x0040
#define ADVERTISE_1000XHALF      0x0040
#define ADVERTISE_100HALF        0x0080
#define ADVERTISE_1000XPAUSE     0x0080
#define ADVERTISE_100FULL        0x0100
#define ADVERTISE_1000XPSE_ASYM  0x0100
#define ADVERTISE_100BASE4       0x0200
#define ADVERTISE_PAUSE_CAP      0x0400
#define ADVERTISE_PAUSE_ASYM     0x0800
#define ADVERTISE_XNP            0x1000
#define ADVERTISE_RESV           ADVERTISE_XNP
#define ADVERTISE_RFAULT         0x2000
#define ADVERTISE_LPACK          0x4000
#define ADVERTISE_NPAGE          0x8000
#define ADVERTISE_FULL           (ADVERTISE_100FULL | ADVERTISE_10FULL | ADVERTISE_CSMA)
#define ADVERTISE_ALL            (ADVERTISE_10HALF | ADVERTISE_10FULL | ADVERTISE_100HALF | ADVERTISE_100FULL)

/* Link partner ability register (MII_LPA) */
#define LPA_SLCT                 0x001f
#define LPA_10HALF               0x0020
#define LPA_1000XFULL            0x0020
#define LPA_10FULL               0x0040
#define LPA_1000XHALF            0x0040
#define LPA_100HALF              0x0080
#define LPA_1000XPAUSE           0x0080
#define LPA_100FULL              0x0100
#define LPA_1000XPAUSE_ASYM      0x0100
#define LPA_100BASE4             0x0200
#define LPA_PAUSE_CAP            0x0400
#define LPA_PAUSE_ASYM           0x0800
#define LPA_RESV                 0x1000
#define LPA_RFAULT               0x2000
#define LPA_LPACK                0x4000
#define LPA_NPAGE                0x8000
#define LPA_DUPLEX               (LPA_10FULL | LPA_100FULL)
#define LPA_100                  (LPA_100FULL | LPA_100HALF | LPA_100BASE4)

/* Expansion register (MII_EXPANSION) */
#define EXPANSION_NWAY           0x0001
#define EXPANSION_LCWP           0x0002
#define EXPANSION_ENABLENPAGE    0x0004
#define EXPANSION_NPCAPABLE      0x0008
#define EXPANSION_MFAULTS        0x0010
#define EXPANSION_RESV           0xffe0

/* Extended status register (MII_ESTATUS) */
#define ESTATUS_1000_XFULL       0x8000
#define ESTATUS_1000_XHALF       0x4000
#define ESTATUS_1000_TFULL       0x2000
#define ESTATUS_1000_THALF       0x1000

/* N-way test register (MII_NWAYTEST) */
#define NWAYTEST_RESV1           0x00ff
#define NWAYTEST_LOOPBACK        0x0100
#define NWAYTEST_RESV2           0xfe00

/* tx_config_Reg[15:0] for SGMII in-band auto-negotiation */
#define ADVERTISE_SGMII          0x0001
#define LPA_SGMII                0x0001
#define LPA_SGMII_SPD_MASK       0x0c00
#define LPA_SGMII_FULL_DUPLEX    0x1000
#define LPA_SGMII_DPX_SPD_MASK   0x1C00
#define LPA_SGMII_10             0x0000
#define LPA_SGMII_10HALF         0x0000
#define LPA_SGMII_10FULL         0x1000
#define LPA_SGMII_100            0x0400
#define LPA_SGMII_100HALF        0x0400
#define LPA_SGMII_100FULL        0x1400
#define LPA_SGMII_1000           0x0800
#define LPA_SGMII_1000HALF       0x0800
#define LPA_SGMII_1000FULL       0x1800
#define LPA_SGMII_LINK           0x8000

/* 1000BASE-T control register (MII_CTRL1000) */
#define ADVERTISE_1000FULL       0x0200
#define ADVERTISE_1000HALF       0x0100
#define CTL1000_PREFER_MASTER    0x0400
#define CTL1000_AS_MASTER        0x0800
#define CTL1000_ENABLE_MASTER    0x1000

/* 1000BASE-T status register (MII_STAT1000) */
#define LPA_1000MSFAIL           0x8000
#define LPA_1000MSRES            0x4000
#define LPA_1000LOCALRXOK        0x2000
#define LPA_1000REMRXOK          0x1000
#define LPA_1000FULL             0x0800
#define LPA_1000HALF             0x0400

/* Flow control flags */
#define FLOW_CTRL_TX             0x01
#define FLOW_CTRL_RX             0x02

/* MMD access control register fields */
#define MII_MMD_CTRL_DEVAD_MASK  0x1f
#define MII_MMD_CTRL_ADDR        0x0000
#define MII_MMD_CTRL_NOINCR      0x4000
#define MII_MMD_CTRL_INCR_RDWT   0x8000

/* ifreq's ifr_data payload for SIOCGMIIPHY / SIOCGMIIREG / SIOCSMIIREG.
   Four __u16 is 8 bytes on every target, which is what the test asserts --
   the field list agreeing is not the same claim as the layout agreeing. */
struct mii_ioctl_data {
	__u16 phy_id;
	__u16 reg_num;
	__u16 val_in;
	__u16 val_out;
};

#endif
