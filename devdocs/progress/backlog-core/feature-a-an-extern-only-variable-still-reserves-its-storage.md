---
slug: feature-a-an-extern-only-variable-still-reserves-its-storage
title: "An imported variable still reserves .bss it can never address"
track: A
prio: 25
type: feature
status: backlog
created: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "A variable declared only `extern` (C) or `external` (Pascal) is emitted as an UND symbol and every reference is retargeted to it -- but AllocFromDeclTypeDesc has already reserved its storage, and the slot stays in .bss unaddressed. Measured: a TU containing `extern int Big[1000];` has exactly the same bss= as one containing `int Big[1000];` (42156B both), so the object carries 4000 bytes it can never reach. Wasted space, never a wrong value. Both frontends."
---

# An import pays for storage it cannot use

The reservation happens at declaration time and the import decision is a fold
over every declaration of the name, so the allocator cannot know. By the time
`SymObjDataExternOnly` is final the slot exists.

Measured with the same program either side of one keyword:

```
extern int Big[1000];  int get(void){return Big[3];}    bss=42156B
       int Big[1000];  int get(void){return Big[3];}    bss=42156B
```

Harmless in the sense that matters — the writer routes every reference to the
UND symbol, so nothing reads the dead slot — and it is why this is prio 25
rather than a bug. It costs object size, which is the same currency as
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]
and worth folding into whatever measurement that one does.

## The shape of a fix

Not "do not allocate": the fold is not final until the translation unit ends,
and a name that looked like an import can still become a definition (C 6.9.2's
tentative definition, which is busybox's dominant shape). So it is a
RECLAIM at end of unit, or a second .bss pass that lays out only the symbols
that survived as definitions. The second is the honest one and it is not small.

Worth checking first whether real inputs make it worth anything: busybox's
`libbb.h` declares a lot of names into 41 translation units, so the multiplier
may be larger than the single-file number suggests.
