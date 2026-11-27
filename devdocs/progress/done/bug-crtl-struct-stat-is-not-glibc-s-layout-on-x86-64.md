---
slug: bug-crtl-struct-stat-is-not-glibc-s-layout-on-x86-64
track: C
prio: 80
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (pxx-built libwlroots linked into gcc-built Panorama, a test setup)
tags: [crtl, abi, system-libs]
summary: "crtl's struct stat was 120 bytes with st_mode at 16 and st_nlink at 24; x86-64's (kernel asm/stat.h, glibc) is 144 bytes with nlink at 16, mode at 24, a pad after gid and three reserved longs. crtl fills its own struct by field name, so crtl programs never noticed, but an --emit-obj --system-libs object hands it to glibc's fstat, which wrote 24 bytes past its end and every field after st_ino into the wrong member. On x86-64 struct stat and stat64 are now glibc's layout exactly; other targets unchanged (feature-crtl-struct-stat-is-the-host-libc-layout-on-every-target)."
---

# struct stat was not glibc's layout on x86-64

Measured with offsetof/sizeof under gcc and pxx:

```
gcc: stat 144 ino 8 mode 24 size 48 mtim 88
pxx: stat 120 ino 8 mode 16 size 48 mtim 88
```

wlroots calls `fstat` (util/shm.c, render/allocator, backend/drm). In
the pxx-object build those calls are glibc's, so each was a 24-byte stack
overrun, with `st_mode` reading the nlink. The test setup ran without it showing,
which is luck, not evidence.

Fix: under `__x86_64__`, struct stat and struct stat64 follow asm/stat.h
(st_dev, st_ino, st_nlink, st_mode, st_uid, st_gid, __pad0, st_rdev, st_size,
st_blksize, st_blocks, the three timespecs, __glibc_reserved[3]). crtl's
src/sys/stat.c assigns by name, so nothing else changed. The 13 existing
stat tests (cstat_fields, c_stat_rdev_decodes, cfileops, c_os_symlink, ...)
give the same results, against gcc where they compile under gcc.

Test: c_syshost26 fstat()s a tmpfile through glibc into a struct followed by a
canary: size 13, S_ISREG, nlink 0, canary intact.
