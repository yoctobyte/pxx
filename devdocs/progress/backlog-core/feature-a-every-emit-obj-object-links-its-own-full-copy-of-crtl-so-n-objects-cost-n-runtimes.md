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
