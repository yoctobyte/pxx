---
slug: feature-c-plain-emit-obj-bakes-c-initialisers
title: "Every x86-64 C --emit-obj bakes its file-scope initialisers into .data, not only a --function-sections one"
track: C
type: feature
prio: 40
status: done
owner: claude-dupwt
found: 2026-11-20
found-by: claude-dupwt (the CAVEAT in backlog-cfront/meta-c-netbsd-rump-kernel-through-pxx.md)
---

# Plain --emit-obj bakes C initialisers

## Before

CStaticDataMode (initialised C globals as bytes + relocations in .data) was
the default only for `--emit-obj --function-sections` on x86-64. A plain
`--emit-obj` object ran its initialisers as stores in the init thunk. Until
.init_array ran, such a global was zero. A NetBSD link-set entry
(`static int *p1 = &lsv` in `link_set_foo`) therefore read NULL to anything
that walked the set before constructors. gcc's object has the bytes and the
relocation at load time. The rump repro `~/rump-pxx-work/s01/s01.c`, built by
latest-e592d024e8: `lsv` in `.bss.lsv`, filled by the thunk.

## Now

The default drops the `FunctionSections` condition: x86-64, `--emit-obj`, not
`--shared`, not `--no-c-static-data`. The same s01 build puts `lsv` in
`.rodata.lsv`, and `link_set_foo` carries its relocation. `--no-c-static-data`
still restores the stores.

## Verified

The test-emit-obj tally ran to its end with exactly one red: the 4a-bis
identity row (plain vs `--function-sections`, linked, allocatable sections
compared). It passed `--no-c-static-data` only to the flagged arm, because
only that arm used to bake. It now passes it to both arms, and the row is
green ("allocatable content identical, +2 thunk symbols"). Gate quick GREEN.
Rainyday's objects are unchanged: `--freestanding` already set
CStaticDataMode.
