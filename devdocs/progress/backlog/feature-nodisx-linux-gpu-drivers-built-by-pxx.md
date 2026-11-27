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
