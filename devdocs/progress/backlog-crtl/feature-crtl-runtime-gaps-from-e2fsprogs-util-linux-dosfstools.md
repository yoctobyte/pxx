---
slug: feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools
track: C
prio: 50
type: feature
status: backlog
created: 2026-11-16
found-by: pixx-cc, building disk tools for pixx at 2491105c8d (repros: /data/projects/pixx/work/tooltest/repro/)
tags: [crtl]
blocked-by: []
summary: "Missing in crtl: sbrk, secure_getenv, the *64 I/O family (pread64, pwrite64, lseek64, stat64, off64_t), posix_memalign, qsort_r, mbstowcs/wcstombs/mbtowc, <err.h>, _POSIX_VDISABLE, CPU_ISSET_S, pthread_atfork. Also suggested: busybox_diff.sh `_pair` entries to enable applet sub-options (fdisk:FEATURE_FDISK_WRITABLE, FEATURE_GPT_LABEL, FEATURE_FDISK_ADVANCED, mkdosfs:MKFS_VFAT; FDISK_SUPPORT_LARGE_DISKS needs off64_t/lseek64)."
---
