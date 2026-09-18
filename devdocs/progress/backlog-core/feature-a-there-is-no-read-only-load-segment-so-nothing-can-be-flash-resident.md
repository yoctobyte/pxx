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
summary: "FIRST CUT LANDED 2026-09-18 (frankH): x86-64 executables load the string-literal pool through a third PT_LOAD with flags R (static and dynamic links, -g included; --no-ro-data turns it off). The compiler's own image: 555 KB of its 574 KB data is now read-only. Mechanism: ranges of Data[] are marked at emission (RoRangeAdd), the writer permutes them to the front and every data address resolves through DataRemap, so no emitter changed. The segment found a real writer on day one -- x86-64's inlined SetLength released the old block with no MSTR_STATIC_RC guard, decrementing a literal's count -- fixed in the same change. REMAINING: ESP-IDF .rodata in the object writers (gcc emits .rodata + .rela.rodata on both riscv32 and xtensa, so relocations are fine); aarch64/i386/arm32 hosted; then RTTI/VMT, dispatch tables, float constants, each after its own never-written measurement. Typed constants stay writable ({$J+}). The bare ESP profile gains nothing -- a fact about OUR profile (one RWX IRAM region, qemu's shape), not the chip."
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

## 2026-09-18 (frankH) — first cut landed: literal pool, x86-64 executables

**What it does.** `InternStr` marks each string entry, size word to padding, as a
read-only range (`RoRangeAdd`; adjacent ranges merge, so a run of literals is one
range). `writeELF` decides the split after the last append to `Data[]`
(`RoLayoutPrepare`), lays the read-only pieces out first and the RW pieces a page
higher in memory than in the file (the usual linker trick: `p_vaddr = p_offset`
mod page, so no page of zero padding in the file), and every data address goes
through `DataRemap`/`DataVA`: fixups, GlobFix data parts, DataPtrFix targets, the
GOT slots and dynamic table pointers, PT_INTERP/PT_DYNAMIC, the DWARF location of
a data-resident global, and the `-g` section table. Every piece keeps its offset
modulo 16, so any alignment an emitter asked for still holds. `Data[]` is
permuted LAST, after every patch into it. `DataLen` is unchanged, so `ok: data=`
still reports emitted bytes. One more program header, so code starts 56 bytes
later; `--proc-map` accounts for it.

**Measured.** Self-host fixedpoint with the split on (`converged`). `readelf -lW
compiler/pascal26`: `LOAD ... R` of 0x878a0 bytes, RW data 0x540c. A hello
world: R 0x1150, RW 0xa88. Dynamic link (libc `strlen` on a literal) runs, with
PT_INTERP/PT_DYNAMIC resolved into the RW part. `test_static_string_literals`,
`test_const_record_in_data` and `test_const_array_in_data` print identically with
and without `--no-ro-data` at default, `--threadsafe`, `-O3` and `-g`.
`gate.sh quick` GREEN.

**Positive control is a Makefile row:** `test_ro_data_literal_store` stores
through `PChar(s)` into a literal. It must die with rc=139, and the same source
under `--no-ro-data` must print `after: Xiteral` rc=0. Checked it can fail: the
fault row fed the `--no-ro-data` binary reports a MISMATCH.

**The segment found a writer the watchpoint probe missed.** x86-64's inlined
`SetLength` (both the resize and the `SetLength(s, 0)` arm) released the old block
through `EmitAnsiStrReleaseLocked`, which had no `MSTR_STATIC_RC` guard. Its retain
twin and the release blob both have one. `a := 'abcdef'; SetLength(a, 3)` did
`dec qword [literal-16]`: silent while the pool was writable, and one step below
the threshold every other guard tests, so from then on that literal was
live-counted. It SIGSEGVed `test_static_string_literals` and the compiler itself
on 4 of 60 lib/rtl root units (gate's head-rtl canary). Fixed by adding the
guard. Other backends release through `PXXStrDecRef`, which is guarded.

**Why the watchpoint probe missed it is NOT established.** That probe's rows
included SetLength, yet evidently never reached this arm with the WATCHED literal
as the old block. Its caveat still stands on its own terms and is written into the
done ticket: gdb `watch` reports value CHANGES, so the first control (+0) did not
trip, and a same-value rewrite would not show. Neither caveat explains this miss.
The R segment has neither blind spot: it faults on any store, of any value, on
any path the run reaches.

**Profile, not chip.** "Bare gains nothing by construction" above is a fact about
OUR bare profile, which loads code+data+bss into one RWX IRAM region because
that is qemu's shape (defs.inc:2275). A real C3 can execute in place from flash,
so a bare profile that mapped flash would gain. That profile's ceiling is this
ticket's floor there, not the chip's.

**ESP-IDF relocations are settled on both ISAs.** riscv32 was measured earlier.
frankb-56 ran xtensa-esp-elf-gcc 15.2.0 (crosstool-NG esp-15.2.0_20251204),
`-O2 -c`, on `const char *const names[] = {"alpha","beta"};`. Result: `.rodata`
flags A (not writable) plus `.rela.rodata` with 2x R_XTENSA_32 against
`.rodata.str1.4`. So a read-only section can carry relocations in an IDF object.
Scope of that: one gcc, one version, one -O. It says the ELF model and the IDF
link allow it, not that pxx's object writer will produce it. That writer is the
next half of this ticket.
