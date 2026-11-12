---
track: B
tags: [C, crtl, busybox]
prio: 40
type: feature
blocked-by: []
summary: "A pxx-built busybox can run a root filesystem (Gibux's initramfs -> disk root, 2026-11-13): crtl's chroot() goes through SYS_chroot instead of being an ENOSYS stub, and tools/busybox_diff.sh turns on FEATURE_MOUNT_FLAGS when `mount` is asked for (--move/--bind reach the kernel as MS_MOVE/MS_BIND, not option text), FEATURE_STAT_FILESYSTEM for `stat` (stat -f), and maps an `sh` applet to SH_IS_ASH (/bin/sh). The 394 list plus `sh` built --freestanding is GREEN, byte-identical to the gcc oracle over 940 cases."
status: done
owner: unassigned
---

# busybox for a root filesystem: sh, mount --move, stat -f, chroot

The Gibux peer asked for these. Its root-on-disk test (tools/roottest.sh)
needs mount --move, switch_root, chroot and stat -f, and every `#!/bin/sh`
script needs /bin/sh.

## Changes

- **lib/crtl/src/unistd.c**: chroot() calls `syscall(SYS_chroot, path)`, the
  way sys/mount.c does mount/umount2/pivot_root. A target without SYS_chroot
  still returns ENOSYS.
- **tools/busybox_diff.sh**: the tree's .config is regenerated on every run
  (allnoconfig plus the applet list), so a hand edit to it would not stick.
  Instead, REQUIRED_ON gains knobs that depend on which applets are asked for:
  - mount → FEATURE_MOUNT_FLAGS;
  - stat → FEATURE_STAT_FILESYSTEM;
  - sh → SH_IS_ASH.

  `sh` used to be unmappable (there is no CONFIG_SH) and was dropped from the
  394 list for that reason. These knobs share the existing staleness test
  (required_knobs_ok) and the existing check that oldconfig did not drop them.
- **tools/busybox-applets-394.txt** is unchanged as a scope. Its header now
  says to append `sh` for a root filesystem: that makes 395, a different
  scope, not to be cited as 394.

## Checked

- test/c_crtl_chroot_reaches_the_kernel.c, a Makefile row, is compared with
  gcc's output at run time (root and non-root answer differently):
  - non-root gives ENOENT for a missing path and EPERM for "/";
  - the stub gave ENOSYS for both;
  - the d9a0d9a599 compiler prints ENOSYS.
- `busybox_diff.sh --keep --freestanding --targets x86_64 --applets "<394> sh"`
  printed busybox-diff: GREEN, byte-identical to the gcc oracle over 940
  cases. Run on the binary:
  - `sh -c 'echo $((6*7))'` prints 42;
  - `stat -f /` works;
  - strace shows `mount --move` as `mount(.., MS_MOVE|MS_SILENT, ..)`;
  - chroot reports the kernel's ENOENT.
- The binary is saved at ~/gibux-payload/busybox-394sh (sha256 d33cafd04324…).
