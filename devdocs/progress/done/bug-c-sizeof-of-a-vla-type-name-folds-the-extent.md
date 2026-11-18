---
track: C
tags: [cfront, sizeof, vla, rump, netbsd]
prio: 50
type: bug
blocked-by: []
summary: "`sizeof(struct s [n - 1])` with a run-time n (NetBSD rumpdev_bus_dma.c) folded n as 0 and refused \"array dimension is negative (-1)\". A run-time extent in an abstract array type-name now makes sizeof a run-time product, size_t-typed. rump-pxx g31."
status: done
owner: pxx2
---

# sizeof of a VLA type name

ParseCSizeof's abstract-array loop uses the declaration path's VLA test
(CConstExprSawNonConst, rewind, ParseCExpr) and returns
`extents * (element size * constant extents)` as tyNativeUInt.

Test: test/c_rump_small_fold.c against gcc, x86-64 and i386.
