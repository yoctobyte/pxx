---
title: "Nodisx: the Linux GPU drivers (radeon, amdgpu, i915, nouveau) built on site by pxx"
status: backlog
owner: ""
prio: 60
area: nodisx
created: 2026-11-27
found-by: umbrella-nodisx-compiles-the-whole-system-on-site-with-pxx (item 7)
---

Item 7 of the closed Nodisx umbrella. **Owner 2026-11-27: "that'd be awesome if we can compile them" -- unparked, next after dhcpcd privsep (claude-dupwt).** The owner decided on 2026-11-21 that
the GPU drivers are built with gcc for now, and that building them with pxx
is "a question for another time". They also need `objcopy --redefine-syms`,
ar, bash and awk. pxx's --rename-globals (325cfaf93a) already covers the
objcopy part for rumpnic.

First step when it is time: a trial compile through Rainyday's
`tools/rump-pxx/pxxcc.py`, to size the gap.

## First census, 2026-11-27 (claude-dupwt)

Rainyday already builds the drivers with gcc as user-space `drmhost`
processes (drivers/gpu, ticket 0064 there): bochs+radeon (`drmhost`), amdgpu,
i915 and nouveau, on drm-kmod's DRM core and FreeBSD's LinuxKPI. radeon runs
on the owner's card. The census logged every gcc compile of those four
binaries (2104 commands, Rainyday 179dfaa) and replayed them through pxx
with Rainyday's tools/rump-pxx/pxxcc.py (--freestanding --system-libs
-include gcc-predef.h). Scratch: /data/tmp/nodisx-dupwt/gpu.

Before any fix, 2093 of 2100 failed at their FIRST error:
- 1813: C23 `enum name : uint8_t { ... }` (FreeBSD's __enum_uint8_decl,
  used whenever __GNUC__ >= 13; sys/vnode.h's VNON is the first hit)
- 241: "too many C macros" (amdgpu's and nouveau's register headers)
- 33: x86 flag-output asm constraints (`=@cce`)
- 1: float arithmetic under --freestanding (amdgpu DC's FPU code)
- a few singles (to read after the big three)
Fixed on the way: an empty include file was "not found" (LinuxKPI's
placeholder headers; bug-cpp-an-empty-include-file-is-reported-not-found).
Harness note: pxxcc.py pins a relative `-include` to the cwd, but gcc
searches -I for it (drivers/gpu's `-include rd-nouveau.h`). My copy
resolves it like gcc; tell the Rainyday session.
Each fix will expose the next error behind it, so this is iterative.
Then the link: binutils-free (--rename-globals for redefine.syms, pxx
--link for the archives).
