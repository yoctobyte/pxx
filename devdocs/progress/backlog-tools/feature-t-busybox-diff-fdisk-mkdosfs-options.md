---
slug: feature-t-busybox-diff-fdisk-mkdosfs-options
track: T
prio: 40
type: feature
status: backlog
created: 2026-11-19
found-by: pixx-cc (in feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools)
tags: [busybox, crtl]
blocked-by: []
summary: "Add busybox_diff.sh `_pair` entries so pixx's disk tools build with their useful options: fdisk:FEATURE_FDISK_WRITABLE, fdisk:FEATURE_GPT_LABEL, fdisk:FEATURE_FDISK_ADVANCED, fdisk:FDISK_SUPPORT_LARGE_DISKS, mkdosfs:MKFS_VFAT. The crtl side (off64_t, lseek64) has existed since 2026-11-19; what is left is a busybox build with these on, plus the diff cases."
---

# busybox_diff: fdisk and mkdosfs sub-options

Split from the crtl-gaps ticket, which is now done. FDISK_SUPPORT_LARGE_DISKS
needed off64_t and lseek64; crtl has had both since 2026-11-19, including a
real `_llseek` on i386 and arm32. Next steps:

1. Add the pairs to the `for _pair in ...` list in tools/busybox_diff.sh
   (line ~608).
2. Build busybox with fdisk and mkdosfs enabled.
3. Compare against the host binaries on a scratch image file, never on a
   real device.
