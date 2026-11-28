---
title: "C: a static initialiser `&(&global)->member` was not a constant address"
status: done
owner: claude-dupwt
prio: 75
area: cfront
---

FreeBSD's SYSCTL_CHILDREN(oid_ptr) is `(&(oid_ptr)->oid_children)`, and every
static sysctl node initialises its parent with it: `&(&sysctl___hw)->...`. The
AST is ADDR(FIELD(DEREF(ADDR(ident)))). CBakeAddrOf had no DEREF arm, so the
address was not a constant. Hosted, it became a start-up store. Under
--freestanding it was refused: "its initialiser is not a constant this
compiler can place in .data". That hit drm-kmod's radeon, ttm and LinuxKPI
module parameters and the SYSUNINIT entries (drm_drv.c), the first failures
in the eighth GPU-driver census (feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix (ir.inc, CBakeAddrOf): `*&x` is x.

Test row c_sinitaddr26 (test/c_static_init_address_of_member_through_address.c)
runs hosted against gcc's output and also builds as a --freestanding object.
