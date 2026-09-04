/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_IF_VLAN_H
#define PXX_CRTL_LINUX_IF_VLAN_H 1

/* THIS FILE IS THE UAPI <linux/if_vlan.h> AND NOTHING MORE. A first cut also
   carried VLAN_HLEN, VLAN_ETH_ALEN, VLAN_N_VID and struct vlan_hdr, which look
   like they belong here and are NOT in the kernel's user-facing header at all
   -- they are kernel-internal, so there is no oracle for them and the values
   would have been mine rather than measured. `gcc' rejecting the probe that
   used them is what caught it. Removed: a constant nobody can diff is a
   liability, and the accept-more direction is only free when what we accept is
   still correct.

   busybox uses the flags from networking/libiproute/iplink.c (through
   IFLA_VLAN_FLAGS) and the ioctl commands from networking/vconfig.c. Both sets
   travel to the kernel, so a wrong value does not fail to compile -- it asks
   for a different thing. */

enum vlan_ioctl_cmds {
    ADD_VLAN_CMD,
    DEL_VLAN_CMD,
    SET_VLAN_INGRESS_PRIORITY_CMD,
    SET_VLAN_EGRESS_PRIORITY_CMD,
    GET_VLAN_INGRESS_PRIORITY_CMD,
    GET_VLAN_EGRESS_PRIORITY_CMD,
    SET_VLAN_NAME_TYPE_CMD,
    SET_VLAN_FLAG_CMD,
    GET_VLAN_REALDEV_NAME_CMD,  /* if this works, it is a VLAN device */
    GET_VLAN_VID_CMD            /* the VID of this VLAN, by name */
};

enum vlan_flags {
    VLAN_FLAG_REORDER_HDR    = 0x1,
    VLAN_FLAG_GVRP           = 0x2,
    VLAN_FLAG_LOOSE_BINDING  = 0x4,
    VLAN_FLAG_MVRP           = 0x8,
    VLAN_FLAG_BRIDGE_BINDING = 0x10
};

#endif
