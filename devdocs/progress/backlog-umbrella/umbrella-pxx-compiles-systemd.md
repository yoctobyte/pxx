---
slug: umbrella-pxx-compiles-systemd
title: "pxx compiles systemd, and the result boots as PID 1"
track: C
prio: 50
type: umbrella
status: open
created: 2026-11-27
found-by: owner (yoctobyte), via pixx-cc
owner: pxx2
blocked-by: []
summary: "Toss systemd at pxx: a large, modern, all-C code base (GNU C everywhere: cleanup attributes, typeof, statement expressions, _Generic, a lot of Linux UAPI). Done when systemd's own test suite passes on the pxx build as on gcc's, and the pxx-built systemd boots a userland to multi-user in QEMU on Linux (later on Rainyday, whose side is its own ticket there). Not for today; meant as a long-running stress source."
---

# pxx compiles systemd

Owner, 2026-11-27: *"gnome or systemd would be things that challenge the
kernel. and pxx."* and *"pxx improves fastest by just tossing code at it."*

systemd is all C (no C++), so it is a fair target now. It leans hard on
GNU C:
- `__attribute__((cleanup))` (the `_cleanup_free_` style is everywhere);
- typeof, statement expressions, _Generic and _Static_assert;
- `__builtin_*` (overflow, constant_p, types_compatible_p);
- section tricks (`_section_("SYSTEMD_...")` arrays read back by name);
- and every corner of Linux UAPI: netlink, BPF, seccomp, mount API,
  pidfd, cgroups, fanotify, keyring.

That makes it a good source of cfront and crtl tickets, like the GPU
census was.

## How

- Pin the current stable release (URL + sha256).
- systemd builds with meson. As with the tools/nodisx recipes, record once
  on a build host: meson setup with gcc as the reference, and take the
  compile list from `compile_commands.json` plus the generated sources
  (python and gperf outputs). Then replay it through pxx. The meson replay
  is a generic tool that GLib/GTK and Panorama's wlroots need too: give it
  a child ticket.
- Dependencies, each compiled by pxx too: libcap, libmount/libblkid
  (util-linux is done in tools/nodisx), libseccomp, libxcrypt, kmod,
  optionally openssl, acl, xz/zstd/lz4 (xz and zstd done).
- Start with a census as claude-dupwt did for the GPU drivers: every
  compile command, replayed, first errors grouped. Fix and re-run.

## Slices

1. **libsystemd + libudev for Panorama** (pxx2, started 2026-11-28): sd-bus,
   sd-event and libudev, static, compiled by pxx (`--shared-runtime
   --threadsafe`) for the all-pxx Panorama link. Method: meson setup with
   most features off, `ninja` only the two static libraries, then replay the
   units those targets built. Census and first-error groups go here as they
   come. Needs libcap compiled by pxx first (also on the dependency list
   above).

   Census, systemd 259 (meson --auto-features=disabled, static-libsystemd,
   static-libudev; 662 units = 209 libsystemd.a + 453 libudev.a, which
   carries its own copies of basic/ and shared/):
   - libcap 2.75 (plain make, ccrec): 7/7 after feature-crtl-pipe2.
   - 2026-11-28 start: 150/662. First errors: 187 host <uchar.h>/<printf.h>
     dragging glibc bits/floatn.h, 134 _Generic, 110 __builtin_imaxabs.
   - after feature-crtl-uchar-h, feature-crtl-printf-h-parse-printf-format,
     feature-c-builtin-abs-family, feature-c-generic-on-a-cast-or-conditional-pointer:
     392/662. Next groups: incomplete struct statx (68) and other
     incomplete-type sizeofs (49), pthread_mutex_t/pthread_t in a struct (39),
     _Generic leftovers (18), LINE_MAX, gettid, struct iovec, typeof.
   - after feature-crtl-statx-file-handle-open-how,
     feature-crtl-pthread-types-in-sys-types-h, feature-crtl-dirent64-and-getdents64:
     487/662. Next: _Generic over pointer expressions pxx cannot yet type
     (49: struct members, call results, const arrays, p[i], p + n; pointee
     const is tracked for variables only), then a tail of crtl names
     (LINE_MAX 12, gettid 10, AT_NO_AUTOMOUNT, syncfs, exp10, close_range,
     renameat2, AF_*, PR_*, ...) and typeof of an untyped expression (7).

## Done when

1. Every unit compiles with pxx (census at 0 failures).
2. `meson test` (systemd's own unit tests) gives the same results on the
   pxx build as on gcc's.
3. The pxx-built systemd boots a userland (Debian or Arch rootfs, its
   systemd replaced) to multi-user.target in QEMU on Linux.
4. Later, on Rainyday: the kernel side is Rainyday's own ticket. Gaps
   found there go to the rainyday session, not worked around here.

No workarounds: systemd's source stays as upstream wrote it. A construct
pxx refuses is a pxx ticket.
