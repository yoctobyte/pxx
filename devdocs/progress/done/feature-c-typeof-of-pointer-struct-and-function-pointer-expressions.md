---
slug: feature-c-typeof-of-pointer-struct-and-function-pointer-expressions
track: C
prio: 60
type: feature
status: done
created: 2026-11-16
found-by: pxx (Gibux seat), rump-pxx g04 g05; pixx-cc B3 (util-linux container_of/min/max, 26 units)
tags: [cfront, typeof, rump]
blocked-by: []
summary: "feature-c-typeof refused typeof of pointer and struct expressions. Now a struct expression takes the record ResolveNodeRec gives; a pointer its pointee kind (CNodePointeeTk) plus record (CNodePtrElemRec, trusted only for a C record id when the pointee is a record or the unmodelled default: `&arr[0]` carries an unrelated id beside a correct int64) and its call signature (CNodeProcSig), the same triple a pointer typedef carries. So `typeof(p) q`, `typeof(p->member) m`, `typeof(*p) copy`, `typeof(&a[0])` (steps 8 on long), `typeof(fp) f2` (callable) and container_of all match gcc. typeof_unqual / __typeof_unqual__ (gcc 14, NetBSD sys/atomic.h) is accepted as typeof: qualifiers are not part of the type here. `extern __typeof(func) alias; alias(3)` imports alias as an undefined symbol, as gcc does (the alias attribute itself is separate). Test: c_tyof (x86-64 and i386 match gcc)."
---
