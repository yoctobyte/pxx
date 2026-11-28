---
slug: feature-crtl-statx-file-handle-open-how
track: crtl
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1: stx_mask/iov_base on incomplete types, 76 units)
tags: [crtl, linux, systemd]
summary: "glibc under _GNU_SOURCE gives <sys/stat.h> struct statx and statx(), and <fcntl.h> struct iovec (for vmsplice), struct open_how (linux/openat2.h) and struct file_handle with name_to_handle_at/open_by_handle_at. systemd relies on all of them arriving that way: json-util.h uses struct iovec having included only <fcntl.h>, stat-util.h reads stx_mask. crtl now does the same: new <linux/stat.h> and <linux/openat2.h> from the UAPI layouts in statx(2)/openat2(2), AT_STATX_*, MAX_HANDLE_SZ, and the three calls as raw syscalls. Test c_statx26: every offset against gcc, statx() against stat(), ENOENT, a file handle; static crtl and through pxx --link."
---

# statx, file handles, open_how
