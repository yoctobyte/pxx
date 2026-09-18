---
slug: feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident
title: "There is no read-only LOAD segment, so every byte of constant data is writable RAM"
track: A
prio: 70
type: feature
blocked-by: []
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

## 2026-09-18 (frankH) — blockers cleared, mechanism settled before building

**Blockers.** Static literal blocks are measured never-written on x86-64
(default, `--threadsafe`, `-O3`; hardware watchpoints plus a positive control;
see that ticket, now done). The typed-const record ticket is fixed
(`38b12690f`), but it was **never a blocker**: typed constants are WRITABLE in
Pascal (`{$J+}`), so they belong in `.data` whatever this ticket does. Moving
one to a read-only mapping would fault a correct program.
`test_const_array_in_data` writes one on purpose.

**One model, two emitters. Hosted and ESP do NOT want different mechanisms.**

- *Model.* Items are marked read-only at emission, as ranges of `Data[]`. At
  write time `Data[]` is permuted into `[read-only][writable]` and every data
  offset is remapped once. This works without touching emitters because every
  reference into `Data[]` already goes through an explicit offset field:
  `Fixups.DataOff`, `DataPtrFix.DataPos/TargetOff`, `MethodFixups.DataPos`,
  and `GlobFix` offsets carrying `DATA_SYM_BIAS`. The code bytes hold
  `@data + offset` placeholders that the writer resolves, so no emitter changes.
- *Hosted executable:* a third `PT_LOAD`, flags `R`, between `R E` and `RW`,
  page-aligned with `ElfSegAlign` (64 KiB on aarch64, for the reason that
  function gives).
- *ESP-IDF:* the relocatable object gets a `.rodata` section. The object
  writers emit only `.text/.data/.bss` today. IDF's linker script places
  `.rodata` in flash (DROM), which is the whole ESP payoff. **Bare profile gains
  nothing by construction:** it loads code+data+bss into one RWX IRAM region,
  qemu's shape (defs.inc:2275). No bare SRAM figure should ever be attributed
  to this ticket.

**First cut:** the string-literal pool only (static blocks, header included),
hosted x86-64 executables. Candidates after that, each needing its own
never-written measurement first: RTTI/VMT tables (UNMEASURED; class vars or
VMT patching would disqualify them), dispatch tables, float constants.
**The segment is its own instrument:** any runtime store to a moved item is a
SIGSEGV at the store, of any value. That is stronger than the watchpoint probe.

**Coordination:** frankb-56 holds whether RTTI/VMT/methods are EMITTED at all
(the root set). This ticket holds where the survivors LIVE. They compose.
