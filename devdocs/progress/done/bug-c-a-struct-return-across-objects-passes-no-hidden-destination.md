---
track: C
tags: [c, x86-64, abi, gibux]
prio: 70
type: bug
blocked-by: []
summary: "A C call to a struct-returning function defined in ANOTHER object (--emit-obj, called through the GOT) never set r10, the hidden result pointer, so the pxx-compiled callee wrote through garbage. Gibux's procfs -> fs_ipath() faulted at cr2=0. The caller now sets r10 for external calls too."
status: done
owner: claude
---

# A struct return across objects passed no hidden destination

pxx returns aggregates through a caller-owned destination in r10: the callee's
prologue stashes it (EmitAggregateDestStash) and the epilogue fills it. The
x86-64 C call path in ir_codegen.inc set r10 only when the callee was not
ProcExternal. Under --emit-obj, a prototype whose body lives in another object
IS ProcExternal (it is called via `call *GOT`), so r10 kept whatever it held
and the callee stored the struct through it.

Reported by the Gibux session: procfs calls fs_ipath() from kernel/fs/ramfs.c
and faulted at cr2=0. Minimal repro: `struct path mk(struct inode*)` (two
pointers) in a.c, called from b.c, each compiled with --emit-obj and linked
with --link -> SIGSEGV.

Fix: drop the `not ProcExternal` guard. A gcc-compiled callee ignores r10
(scratch in SysV), so nothing that worked before changes. Mixing with gcc
objects that return structs (true SysV sret in rdi, small structs in rax:rdx)
was already unmodelled and still is.

aarch64 has no such guard (it sets the destination for externals already).

Test: test/c_struct_return_across_objects_def.c + _use.c, test-core row
csret_x (two objects, --link). Output matches gcc. The row segfaults without
the fix.
