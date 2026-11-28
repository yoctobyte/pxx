---
title: "C: an array-of-structs member was refused as a struct operand"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

An array member's node carries its ELEMENT kind, so a member such as
`struct drm_mm_node mm_nodes[]` reads as tyRecord. The struct-operand check
(CRefuseRecordOperand) then refused `node = mgr->mm_nodes;`,
`mgr->mm_nodes + 1` and `(struct node *)mgr->mm_nodes` as struct operands.
They are not: an array decays to a pointer to its first element (6.3.2.1p3).
The declaration-initialiser spelling worked, the assignment did not. Hit in
amdgpu_res_cursor.h (gfx_v9_4_2.c and others) in the GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix: a node that decays to a pointer (CNodeDecaysToPointer) is exempt from the
check. Test row c_sarrdec26 covers a flexible member through a call, `n++->`,
indexing and an offset, and its expected output is gcc's.
