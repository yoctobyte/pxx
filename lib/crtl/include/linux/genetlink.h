/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/genetlink.h>, generic netlink: the 4-byte family header
 * that follows the nlmsghdr, and the controller family that maps a family
 * NAME ("nl80211") to the id a request is sent to. dhcpcd's if-linux.c asks
 * the controller for nl80211 to read the SSID.
 */
#ifndef _CRTL_LINUX_GENETLINK_H
#define _CRTL_LINUX_GENETLINK_H
#include <linux/types.h>
#include <linux/netlink.h>

#define GENL_NAMSIZ 16

struct genlmsghdr {
  __u8  cmd;
  __u8  version;
  __u16 reserved;
};
#define GENL_HDRLEN NLMSG_ALIGN(sizeof(struct genlmsghdr))

#define GENL_ADMIN_PERM 0x01
#define GENL_CMD_CAP_DO 0x02
#define GENL_CMD_CAP_DUMP 0x04
#define GENL_CMD_CAP_HASPOL 0x08

/* the controller's own family id is fixed: the first id after the reserved
   netlink message types */
#define GENL_MIN_ID NLMSG_MIN_TYPE
#define GENL_ID_CTRL NLMSG_MIN_TYPE

enum {
  CTRL_CMD_UNSPEC,
  CTRL_CMD_NEWFAMILY,
  CTRL_CMD_DELFAMILY,
  CTRL_CMD_GETFAMILY,
  CTRL_CMD_NEWOPS,
  CTRL_CMD_DELOPS,
  CTRL_CMD_GETOPS,
  CTRL_CMD_NEWMCAST_GRP,
  CTRL_CMD_DELMCAST_GRP,
  CTRL_CMD_GETMCAST_GRP,
  CTRL_CMD_GETPOLICY
};

enum {
  CTRL_ATTR_UNSPEC,
  CTRL_ATTR_FAMILY_ID,
  CTRL_ATTR_FAMILY_NAME,
  CTRL_ATTR_VERSION,
  CTRL_ATTR_HDRSIZE,
  CTRL_ATTR_MAXATTR,
  CTRL_ATTR_OPS,
  CTRL_ATTR_MCAST_GROUPS
};

enum {
  CTRL_ATTR_MCAST_GRP_UNSPEC,
  CTRL_ATTR_MCAST_GRP_NAME,
  CTRL_ATTR_MCAST_GRP_ID
};

#endif
