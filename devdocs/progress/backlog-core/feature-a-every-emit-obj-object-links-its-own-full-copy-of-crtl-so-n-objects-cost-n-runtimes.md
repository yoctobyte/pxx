---
slug: feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes
title: "N objects link N copies of crtl: weak resolves the symbol, it does not drop the bytes"
track: A
prio: 55
type: feature
status: backlog
created: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "Two --emit-obj objects now link and share one runtime (bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link), but WEAK only picks a winner among duplicate symbols -- the losing objects' sections are still linked in whole. Measured: two objects that each contain crtl produce a 580088-byte binary against 310544 for one, and busybox's 41-TU separate build came out at 13.7MB for the same reason. Needs section-granular deduplication: a crtl archive the linker pulls members from, or function/data sections plus COMDAT groups."
---

# N objects cost N runtimes

The collision is fixed and the size is not. A weak definition tells the linker
which `malloc` symbol wins; it says nothing about the 162KB of `.text` the
losing objects still contribute, because inclusion is decided per SECTION and
every object has one big `.text`.

## The two shapes, and they are not equivalent

1. **A crtl archive.** `--emit-obj` stops bundling the runtime; crtl ships as
   `libcrtl.a` and the linker pulls only the members a program references.
   This is what a C toolchain does, it makes the duplicate-symbol question
   disappear rather than answering it, and it is the shape frankD proposed as
   option 2. It changes the INTERFACE: a pxx object stops being self-contained,
   so every consumer needs the archive on its link line.
2. **Function/data sections plus COMDAT groups.** The object stays
   self-contained and `--gc-sections` drops what is unreachable. No interface
   change, but it needs per-symbol sections throughout the backend and a group
   section per runtime entry point.

Worth measuring before choosing: how much of the 310544 a trivial program
actually reaches. If it is most of it, (1) is the only one that pays.

## What must not regress

`test-emit-obj` block 4b-septies asserts two objects share one heap, one
`errno` and one `optind` against a gcc oracle. Under (1) that row still has to
pass with the archive on the link line, and the weak binding stops being what
carries it -- so the row's aim checks (weak FUNC count, weak OBJECT count) would
need rewriting rather than deleting, or they become vacuous rather than false.

## The measurement this ticket asked for, taken

frankA, 2026-09-01, compiler `4fa89436ffe7`. The ticket said to measure how much
of an object a trivial program actually reaches before choosing a shape. It is
essentially all of it, and the measurement turned up a structural fact that
changes the cost of both options.

**1. A one-line program carries the whole runtime.** `int plain_add(int,int)`
produces 421 FUNC symbols and 103083 bytes of `.text`, of which the user's
function is 118 bytes at offset 0x191de — **99.8% of `.text` is before it.**

**2. Nothing already prunes it.** `--dce`, `-O2` and `-O2 --dce` all produce
byte-identical output: `code=103083B procs=429` in every case. So there is no
existing switch to measure against, and the 13.7MB busybox number is 41 copies
of this.

**3. The runtime is contiguous — except for a tail emitted AFTER the user's
code.** `__pxx_fegetround` sits at 0x191cc in every object, immediately before
the user's first proc; `__pxx_run_finalizers` sits after it.

**4. Two objects' runtime prefixes differ in exactly TEN bytes out of 102878**,
and all ten are references from the runtime bulk into that trailing tail:

```
0x000b0b in PXXHeapExhausted   0x0090b0 in PXXVariantError   0x0092bd in PXXRangeError
0x008fc6 in PXXDivZero         0x00915f in PXXInvalidCast    0x0093b1 in PXXExitProcess
0x00920e in PXXOverflow        0x009460 in PXXNilRef
```

Every delta is −36, which is exactly the difference between the two programs'
user code (`plain_add` 118 bytes, `other_fn` 82). Confirmed independently:
`__pxx_run_finalizers` is at 0x19276 in one object and 0x19252 in the other,
36 apart.

## What that means for the two options

**Byte-identity is nearly free and is NOT sufficient.** Emitting the trailing
runtime procs before the user's code would make 102878 bytes of every object
identical — a far smaller change than either option above. But dedup still
fails, because the user's calls INTO the runtime are resolved at emit time as
direct rel32, not relocations: an object has only **7 `.text` relocations in
total**. If the linker keeps object A's runtime copy and discards B's, B's user
code still jumps at a displacement computed for B's own discarded copy.

So the load-bearing prerequisite for BOTH options is the same one: **calls from
user code into the runtime must become relocations against symbols.** The
runtime procs already have LOCAL FUNC symbols, so the names exist; what does not
exist is the decision to relocate rather than resolve. That is the same
substitution as
[[bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link]]
made for DATA references, one layer over.

Rank the work that way: the relocation change is the ticket, and archive vs
COMDAT is a choice made afterwards and cheaply. The ten shifting bytes are worth
fixing in the same pass — they are the tell that emission order splits the
runtime, and a "byte-identical" claim measured before that reorder would be
false by ten bytes with no symptom.
