---
slug: bug-nt-crtl-stat-and-fstat-were-enosys
track: kernels
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pxx (kernels seat): c_os_procfiles.c on ReactOS, then on Wine
tags: [nt, winabi]
blocked-by: []
summary: "Under --os=nt every C stat/fstat/lstat returned -1 with ENOSYS: crtl reaches the PAL through statx (332), which winabi did not map (Pascal's own stat calls use newfstatat, so the Pascal tests never saw it). WinStatx now rewrites WinStatAt's struct stat in statx's layout. Test: test/c_os_procfiles.c, added to test-windows."
---

# C stat/fstat under --os=nt were ENOSYS

`PXX_WINABI_TRACE=1` named it: `winabi: unmapped 0x0000014c`.
