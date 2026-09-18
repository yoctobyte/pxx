---
slug: feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident
title: "There is no read-only LOAD segment, so every byte of constant data is writable RAM"
track: A
prio: 70
type: feature
blocked-by: [feature-opt-static-literal-blocks-should-never-be-written-to, bug-a-a-typed-const-record-is-built-by-startup-code-not-stored-as-data]
status: new
created: 2026-09-18
owner: ""
summary: "pxx emits exactly two LOAD segments — `R E` (code) and `RW` (data+bss). `grep -c rodata` is ZERO in both elfwriter.inc and defs.inc. So string literals, dispatch tables, RTTI blobs and every other never-written constant sit in a writable segment, which on a hosted target costs a page permission and on ESP costs SRAM that could have stayed in flash. Measured 2026-09-18: the data segment of a Pascal hello world is 70.7% zeros and 17.4% ASCII, of which 6,429 bytes across 197 strings are diagnostic text that is never written. Owner directive, 2026-09-17: \"mark as read-only where possible.\" Blocked by the two tickets that make constants actually constant — a saturated-refcount literal block is WRITTEN to today, so marking its page read-only would fault."
---

# What

Two LOAD segments, measured at HEAD:

    LOAD 0x000000 0x400000 FileSiz 0x001000 MemSiz 0x001000 R E
    LOAD 0x001000 0x401000 FileSiz 0x000150 MemSiz 0x00a498 RW

There is no third. Read-only data is not a category this compiler has.

## Why it matters on each half

- **Hosted:** constants are writable. A stray store corrupts a literal instead
  of faulting, and the loader cannot share the pages between processes.
- **ESP:** this is the whole question. Flash is cheap and SRAM is not. A `.rodata`
  segment is the difference between a string table living in flash and living in
  the 400 KB the chip has. Today it has nowhere to go but RAM.

## Why it is blocked rather than ready

Two things currently WRITE to data that ought to be constant, and marking a page
read-only under them would turn a size win into a fault:

- [[feature-opt-static-literal-blocks-should-never-be-written-to]] — the pooled
  literal blocks carry a saturated refcount that the emitters still increment.
- [[bug-a-a-typed-const-record-is-built-by-startup-code-not-stored-as-data]] — a
  typed const record is BSS plus generated stores, so it is not data at all yet.

Take those first, then this is a segment and a section attribute.

## Scope note

`.rodata` is the mechanism, not the goal. The goal is that a constant is
addressable from a read-only mapping — on ESP that means the flash-resident
`.text`/`.rodata` of the IDF profile, not the bare profile's single RWX region.
