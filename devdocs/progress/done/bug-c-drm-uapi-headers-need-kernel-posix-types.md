---
slug: bug-c-drm-uapi-headers-need-kernel-posix-types
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pixx (Rainyday's user/kmstest.c) and pxx2 (libdrm for Path B's Xorg)
tags: [crtl, headers, uapi, drm]
summary: "`#include <drm/drm.h>` failed: `unknown type name '__kernel_size_t'`. The kernel's <linux/types.h> pulls in <linux/posix_types.h>; crtl's shadow of it declared a handful of __kernel_* types inline and not __kernel_size_t, and crtl had no <asm/ioctl.h>, so drm.h's include resolved to the host's. New crtl <linux/posix_types.h> (the whole family, per-arch widths as asm/posix_types_32/64.h: i386's 16-bit mode/uid/gid/ipc_pid, x86-64's 16-bit old_uid) included by <linux/types.h>; the _IOC encoding moved from <sys/ioctl.h> to a new <asm-generic/ioctl.h>, which <sys/ioctl.h> and a new <asm/ioctl.h> include. Test c_drmuapi26: DRM struct sizes, offsets and ioctl numbers against gcc (x86-64; a cross target has no host UAPI tree to read drm.h from)."
---

# DRM UAPI headers need the kernel's posix types

`<drm/drm.h>` on Linux:

```c
#include <linux/types.h>
#include <asm/ioctl.h>
...
	__kernel_size_t name_len;
```

crtl's `<linux/types.h>` is a partial shadow (see its header comment). It
now includes the new `<linux/posix_types.h>`, which carries the whole
`__kernel_*` family with the target's widths. The `_IOC` macros are in
`<asm-generic/ioctl.h>`, the name UAPI headers use, and `<sys/ioctl.h>`
includes that.

Values checked against gcc for DRM_IOCTL_VERSION, the mode-setting and
dumb-buffer ioctls, and the structs they pass.
