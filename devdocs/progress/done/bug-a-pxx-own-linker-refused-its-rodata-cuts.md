---
slug: bug-a-pxx-own-linker-refused-its-rodata-cuts
title: "pxx's own linker refused the .rodata.<name> cuts pxx started emitting"
track: A
type: bug
prio: 70
status: done
owner: claude-dupwt
found: 2026-11-19
found-by: rd (test-core: c_srt*, c_rab_p, c_fpap_s; tools/elf_reader_vs_readelf.sh)
---

# pxx's own linker refused its own `.rodata.<name>` cuts

## Before

7237dd84bf (feature-c-const-objects-go-to-rodata-in-x86-64-objects) put a
baked const C object in `.rodata.<name>`. `ElfLnkSecKind` (elfreader.inc),
the classifier behind `--link` and its section GC, accepted `.rodata*` only
under `--freestanding`, so a hosted `--link` of such an object stopped with
"allocated section '.rodata.in6addr_any' is not one pxx emits". Red rows:
c_srt, c_srt_d, c_srt_dr (and their gc variants), c_rab_p, c_fpap_s, and
tools/elf_reader_vs_readelf.sh (elfgc on '.rodata.__pxx_rnd_deg'). gate
quick runs none of them, so it stayed GREEN and I pushed it.

## Change

A hosted link maps `.rodata.<name>` (type PROGBITS, flags A) to the data
kind: the hosted image has no read-only data segment, and read-only bytes in
a writable page read the same. A bare `.rodata` stays refused, since pxx never
writes one in a hosted object (the elf_reader_vs_readelf positive control
still checks that). The freestanding arm is unchanged and still comes first.

## Measured

elf_reader_vs_readelf.sh completes (reader, GC and link all agree with
binutils); the test-core block from c_srt through c_fpap_s matches its
expected output; gate quick GREEN.

## Lesson

A new section name is a contract with every READER of pxx's objects, and
pxx is one of them. I checked gcc's linker and readelf for 7237dd84bf and
not pxx's own --link.
