---
slug: umbrella-nodisx-compiles-the-whole-system-on-site-with-pxx
title: "Nodisx: everything an installed Rainyday + pixix system needs is compiled on the target by pxx"
track: C
prio: 70
type: umbrella
status: backlog
created: 2026-11-26
found-by: owner (yoctobyte), asked of claude-dupwt
owner: ""
blocked-by: []
summary: "GOAL, not a unit of work. 2026-11-26: GNU make and rumpnic DONE (claude-dupwt); e2fsprogs/util-linux rd; zstd/bzip2 pxx2. The Nodisx installer ISO ships only the kernel, pxx, a boot loader and a small permissive bootstrap set (~/nodisx/docs/bootstrap.md); everything else, GPL included, is pinned source plus a recipe that pxx compiles ON THE TARGET with only pxx, a POSIX shell and toybox (tools/nodisx/README.md). DONE: the kernel builds with pxx; toybox (1604/1604), mksh, dosfstools (GPL-3, images byte-identical to gcc's), xz-utils, the Path B X desktop; 471 rump objects and the USB stack compile, all-pxx rumpnic boots. OPEN, in order: GNU make (gates the kernel on site), mke2fs + sfdisk/blkid, rumpnic/usbhid as on-site recipes, the rest of the bootstrap set (curl+mbedTLS, dhcpcd, dropbear, zstd, bzip2, Limine), pixix userland (busybox, sqlite), and LAST the Linux GPU drivers (owner 2026-11-21: gcc for now)."
---

# Nodisx compiles the whole system on site with pxx

Owner, 2026-11-26: *"ideally we can compile all that a pixx (rainyday kernel)
userland needs. example, compiling gpl drivers with pxx during install
process."*

Nodisx (`~/nodisx`, its `docs/needs.md` is what each part asks for) is the
installer ISO. It carries no GPL binaries: GPL is source on the ISO, compiled
during the install. pxx is the compiler on the image. A recipe is recorded
once on a build host (`record.sh`, which may use gcc to pre-generate what the
tool's own build would generate) and replayed on the target (`onsite.sh`:
pxx, sh, toybox only). Build time on site does not matter; licences do.

**A part is done when** its recipe is in `tools/nodisx/<tool>/`, the on-site
replay runs with pxx + sh + toybox only, and the tool's own test suite passes
on the pxx build as it does on gcc's. Each one gets its own ticket and a line
in Nodisx's `docs/needs.md`.

## Done (2026-11-26)

| part | licence | evidence |
|---|---|---|
| Rainyday kernel | MIT | builds with TOOLCHAIN=pxx (needs GNU make on site) |
| toybox 0.8.15 | 0BSD | 8a0380e405; 1604/1604 own tests |
| mksh R59c | MirOS | 8a0380e405; check.t equal to gcc's |
| dosfstools 4.2 | GPL-3.0 | 221e72dffc; make check 39 PASS; images byte-identical |
| xz-utils 5.6.3 | 0BSD | make check 18/18; output byte-identical |
| Path B desktop (Xorg, libdrm, pixman, JWM) | MIT-ish | c6be450156, 45e7e28a0f; bundle equal host vs. on site |
| rump kernel, rumpnic | BSD | 471/471 objects; all-pxx rumpnic boots (meta-c-netbsd-rump-kernel-through-pxx) |
| rump USB stack | BSD | 353/353 compile; host smoke attaches xhci0/usb0 |
| GNU make 4.4.1 | GPL-3.0 | tools/nodisx/make; own suite 1422/1422; Rainyday kernel built with it byte-identical |
| rumpnic on site | BSD + MIT | tools/nodisx/rumpnic; 473 objects by pxx with no binutils (--rename-globals); boots, e1000 + rtl8139 PASS |
| usbhid | MIT | Rainyday's own C; `make -C drivers PXX=pxx` with the on-site GNU make |

## Open, in the order to take them

1. ~~GNU make~~ DONE 2026-11-26 (claude-dupwt), see the table.
2. **Disk tools** (rd, "pxx" session, 2026-11-26): mke2fs (e2fsprogs 1.47.1), sfdisk and blkid (util-linux
   2.40.2). Without them the installer cannot partition or format.
3. ~~rumpnic and usbhid as on-site recipes~~ DONE 2026-11-26 (claude-dupwt),
   see the table.
4. **The rest of the bootstrap set.** zstd and bzip2: pxx2 session
   (2026-11-26), dhcpcd possibly next. Untried with pxx: curl + mbedTLS,
   dhcpcd, dropbear, zstd, bzip2, Limine (its binary may ship if pxx cannot
   build it: BSD-2).
5. **pixix userland:** busybox (GPL, on site), sqlite, and whatever else
   `install_lib_candidates.sh` carries; check each for build steps that run
   host-compiled helpers.
6. **Linux GPU drivers** (radeon, amdgpu, i915, nouveau; GPL). Owner
   2026-11-21: built with gcc for now, pxx "a question for another time".
   They also need `objcopy --redefine-syms`, ar, bash and awk. First step
   when it is time: a trial compile through Rainyday's
   `tools/rump-pxx/pxxcc.py`, to size the gap.

## Known costs, not blockers

- A recipe is tied to the pxx that recorded it: the ISO ships that pxx.
- `--link` caches the shared runtime in `$XDG_CACHE_HOME`: the installer
  must point it at a writable directory.
- Runtime speed of what pxx builds: xz compresses ~8x slower than gcc -O2
  (no register allocator). On-site build time is free; the installed tools'
  speed is not.
