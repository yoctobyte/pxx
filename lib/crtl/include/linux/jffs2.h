/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_JFFS2_H
#define PXX_CRTL_LINUX_JFFS2_H 1

#include <linux/types.h>

/* JFFS2's on-flash node header, which busybox's flash_eraseall.c writes as a
   clean marker after erasing each block. Values read from the host's
   <linux/jffs2.h>. THE PACKING IS THE POINT: every field is wrapped in a
   one-member struct in the kernel header for the same reason it is here --
   these are little-endian-on-flash quantities, and the wrapper is what stops
   somebody assigning to them without byteswapping. A clean marker written with
   the wrong layout is not a compile error; it is a filesystem the kernel
   mounts and then reports as containing garbage. */
typedef struct { __u32 v32; } __attribute__((packed)) jint32_t;
typedef struct { __u32 m;   } __attribute__((packed)) jmode_t;
typedef struct { __u16 v16; } __attribute__((packed)) jint16_t;

#define JFFS2_MAGIC_BITMASK           0x1985

#define JFFS2_COMPAT_MASK             0xc000
#define JFFS2_NODE_ACCURATE           0x2000
#define JFFS2_FEATURE_INCOMPAT        0xc000
#define JFFS2_FEATURE_ROCOMPAT        0x8000
#define JFFS2_FEATURE_RWCOMPAT_COPY   0x4000
#define JFFS2_FEATURE_RWCOMPAT_DELETE 0x0000

#define JFFS2_NODETYPE_DIRENT       (JFFS2_FEATURE_INCOMPAT | JFFS2_NODE_ACCURATE | 1)
#define JFFS2_NODETYPE_INODE        (JFFS2_FEATURE_INCOMPAT | JFFS2_NODE_ACCURATE | 2)
#define JFFS2_NODETYPE_CLEANMARKER  (JFFS2_FEATURE_RWCOMPAT_DELETE | JFFS2_NODE_ACCURATE | 3)
#define JFFS2_NODETYPE_PADDING      (JFFS2_FEATURE_RWCOMPAT_DELETE | JFFS2_NODE_ACCURATE | 4)

struct jffs2_unknown_node {
    /* every node starts like this */
    jint16_t magic;
    jint16_t nodetype;
    jint32_t totlen;    /* so a reader can skip a node it does not grok */
    jint32_t hdr_crc;
};

#endif
