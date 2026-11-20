---
slug: bug-t-elf-reader-subject-went-16-aligned
title: "elf-reader row: c.o's .text became a multiple of 16, so its alignment guard fired"
track: T
type: bug
prio: 40
status: done
owner: claude-dupwt
found: 2026-11-20
found-by: claude-dupwt (test-core tally)
---

# elf-reader subject went 16-aligned

tools/elf_reader_vs_readelf.sh asserts that its subject c.o has a .text that
is NOT a multiple of 16, so that d.o's .text starts on padding only
per-input alignment produces. After 6cdc4bea7e (plain --emit-obj bakes C
initialisers instead of storing them in the init thunk) c.o's .text shrank
from 0x3ffbe to 0x3dfb0, and the guard fired ("per-input alignment is not
exercised"). The guard was right; the code was not wrong.

Fix: c.c gains `int pad1(int x){ return x + 1; }`, putting .text at
0x3dfea. The whole script passes again (ELF-READER-ORACLE-COMPLETE).
