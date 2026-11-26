---
title: Nodisx -- rumpnic (NetBSD's NIC drivers in a rump kernel) built on site by pxx, boots
status: done
owner: claude-dupwt
prio: 60
area: nodisx
---

# rumpnic on site

Umbrella item 3 (umbrella-nodisx-compiles-the-whole-system-on-site-with-pxx).
tools/nodisx/rumpnic has three scripts:

- `mkunits.py` + `record.sh` (host): writes the compile list of 473 units
  (15 hosted, 8 kernel units not renamed, 432 C and 18 .S kernel units
  renamed) and a source tarball of exactly the files the compiles open
  (strace): 2012 files, 2,340,800 bytes xz.
- `onsite.sh` (target, pxx + sh + toybox): compiles the units, then
  `pxx --link --threadsafe`. NetBSD's `rumpns_` rename is pxx's
  `--rename-globals` (feature-a-rename-globals-for-a-rump-kernel-without-binutils).
- `test.sh` (host): replays the recipe with a PATH that has no gcc,
  binutils or python, then boots it with Rainyday's tools/rumpnictest.sh:
  e1000, and rtl8139 behind an IOMMU as uid 150. Both PASS (DHCP, ping,
  fetch with the md5 checked). Build time on site: 302 s at JOBS=6 on
  plexus. Result: text 6,904,832, data 504,456, bss 1,203,724.

Found on the way: NetBSD's `.S` files (atomics, string routines) went
through pxx's assembler path, which returned before the rename. The link
then missed 34 `rumpns_` names. The rename now runs on that path too.

usbhid needs no recipe of its own: it is Rainyday's own USB stack (MIT,
plain C in drivers/), built by `make -C drivers PXX=pxx` with the on-site
GNU make.
