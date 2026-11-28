---
slug: feature-crtl-dirent64-and-getdents64
track: crtl
prio: 55
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1: sizeof(struct dirent64) incomplete, 49 units)
tags: [crtl, dirent, systemd]
summary: "crtl had no struct dirent64, readdir64 or getdents64. systemd's dirent-util.h asserts struct dirent and struct dirent64 interchangeable field by field, and stat-util.c / recurse-dir.c call getdents64 directly. Added as glibc has them: struct dirent64 and readdir64 under _LARGEFILE64_SOURCE or _GNU_SOURCE (the same layout as crtl's struct dirent, already the kernel's linux_dirent64), getdents64 under _GNU_SOURCE over the PAL's getdents64. Also: the sizeof-of-an-incomplete-type error now names the tag (it did not, so a census group had to be traced by hand). Test c_dir64_26 against gcc."
---

# dirent64 and getdents64
