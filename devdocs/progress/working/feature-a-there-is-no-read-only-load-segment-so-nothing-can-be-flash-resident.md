---
slug: feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident
title: "There is no read-only LOAD segment, so every byte of constant data is writable RAM"
track: A
prio: 70
type: feature
blocked-by: []
status: working
created: 2026-09-18
owner: frankH
summary: "FIRST CUT LANDED 2026-09-18 (frankH): x86-64 executables (aarch64, i386 and arm32 too since 2026-09-19 -- every hosted target) load the string-literal pool through a third PT_LOAD with flags R (static and dynamic links, -g included; --no-ro-data turns it off). The compiler's own image: 555 KB of its 574 KB data is now read-only. Mechanism: ranges of Data[] are marked at emission (RoRangeAdd), the writer permutes them to the front and every data address resolves through DataRemap, so no emitter changed. The segment found a real writer on day one -- x86-64's inlined SetLength released the old block with no MSTR_STATIC_RC guard, decrementing a literal's count -- fixed in the same change. ESP-IDF LANDED 2026-09-18: both ELF32 object writers emit .rodata (flags A) + .rela.rodata, which IDF places in flash -- test_emit_obj.pas on xtensa: SRAM .data 6304 -> 2624 bytes; a literal an iram; routine references directly stays in .data (iram code runs with the flash cache off). RTTI/VMT MEASURED 2026-09-19 (flag --ro-rtti, experimental, off): class RTTI headers + Pascal VMTs read-only -> test-core 2355/2356, the one red the predicted control; not yet default, see the 2026-09-19 section for what the green does NOT cover. lib-test under it: clean too (only the pre-existing xmlreader red). REMAINING: make --ro-rtti the default once a pcl widget program has RUN under it, dispatch tables, float constants, each after its own never-written measurement. Typed constants stay writable ({$J+}). The bare ESP profile gains nothing -- a fact about OUR profile (one RWX IRAM region, qemu's shape), not the chip."
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

## 2026-09-18 (frankH) — test-core sweep: one regression of mine, two exposed defects

borg published five new test-core reds on a tree containing `b05b7bb0a`. Each
was classified with `--no-ro-data` as the A/B before fixing:

- **Segment bug (mine): `test_interface_containers` @1/@2 and
  `test_dynarray_to_pointer_seam_leaks`.** RTTI layout descriptors hold
  SELF-RELATIVE 32-bit words (`typeRef`/`baseTypeRef` = target - pos, decoded
  as `pos + word`; five sites in rtti_emit.inc). The split compacts the RW part,
  so a literal range between two RW items changes their distance. The result was
  a silent wrong value with no fault: rdyn 0 instead of 3, and live=999 instead
  of 14. Fix: `AddDataRelFix` records each word, and `ApplyImageFixups`
  recomputes it through `DataRemap`. The earlier claim in this ticket's model
  ("every reference into Data[] already goes through an explicit offset field")
  was false for these five sites.
- **Exposed pxx bug: `test_indexing_a_string_cast_of_a_pointer_slot`.**
  `t(r)[2] := 'X'` with `r: Pointer` did no copy-on-write. It wrote into the
  literal pool, or into another variable's shared string. Fixed in ir.inc: the
  slot is presented as element 0 of an array-of-AnsiString, so every backend's
  COW path applies. Output matches fpc on five targets. New row K pins the
  aliasing half; the pinned compiler prints `K: KXZde KXZde`.
- **Exposed test bug: `test_cast_deref_varparam`.** The test read a stream
  into `PChar(r)^` straight after `r := 'zzz'`. fpc 3.2.2 faults on the same
  program. Added `UniqueString(r)`; the test's subject is unchanged.

## 2026-09-18 (frankH) — test-core rerun: a second segment bug of mine

The detached rerun stopped at `synthclob26 has no libc.so.6 DT_NEEDED`.
`--no-ro-data` A/B: with the split, NEEDED read `>`; without it, `libc.so.6`.
So this is a segment bug. `PrepareDynamicData` called
`ResolveSynthImportLibraries` after `DynamicStrOff := DataLen`, and resolving a
synthesised soname INTERNS it. That put a 48-byte literal block inside
`.dynstr`. Before the split those bytes were dead and never read. The split
moved them out of the RW image, which shortened the table under its own
offsets. Fix: resolve first, in both builders (the 32-bit copy was latent). A
`roMark` guard now errors if any literal is interned while the tables are
built. The model's blind spot is the same one as the RTTI words: a table whose
integrity is POSITIONAL (offsets from its own start) breaks if a foreign range
is emitted inside it.

## 2026-09-18 (frankH) — ESP-IDF objects: .rodata landed

Both ELF32 object writers (the plain one and the two-text-section `iram;` one)
use the same layout as the executable with no VA shift. RO pieces go into a
`.rodata` section (SHF_ALLOC only) plus `.rela.rodata`. Both are APPENDED after
`.shstrtab`'s index, so no existing section index moves. A data offset becomes
a (section, offset) pair through `ObjDataSym`/`ObjDataOff`. Self-relative RTTI
words are re-patched, and both ends must share a section. Objects with no
split keep their exact old byte layout.

**One deliberate exception: a literal an `iram;` routine references directly
stays in `.data`.** iram code is what runs while the flash cache is off, and
IDF puts `.rodata` in flash. `test_esp_isr_register`'s handler passes a format
string to `esp_rom_printf`, which is that case exactly. C has the same rule and
makes the programmer write `DRAM_STR`; here the compiler sees the reference.
Only DIRECT references count: a `.data` table pointing at a `.rodata` literal is
read through flash, as in C. To support this, `RoRangeAdd` now also records
each block's start (`RoEntryStart`), because merging erased the seams.

Verified by linking with the esp gcc on both ISAs
(`tools/elf_literal_home.py`, rows in `test-emit-obj`). In each case the
literal's bytes sit in `.rodata` (flags A) and the `.text` slot holds exactly
their address. The `--no-ro-data` control lands in `.data` AW. In the iram
fixture, the iram literal stays in `.data` and is referenced from
`.iram1.text`. Not run on hardware: no IDF app build here, so "IDF places it in
DROM" is the linker script's documented behaviour, not a measurement.

Sizes, xtensa, `.data` with the split against without it:
`esp_obj_rodata.pas` 2288 vs 3424 (+1264 .rodata), `test_emit_obj.pas` 2624 vs
6304 (+3832 .rodata). The bare profile is unchanged; it uses the executable
writer and one RWX region.

## 2026-09-18 (frankH) — PARKED for the wind-down: state and next step

**All three live corruptions the segment exposed are FIXED and pushed. None is
open.**
- SetLength's unguarded literal-refcount decrement: `b05b7bb0a`. Pin v411
  carries the bug, so it is inert for pin users until the next pin.
- `t(r)[i] := c` with no copy-on-write: `120e3a3cd`.
- The test that wrote a literal (`test_cast_deref_varparam`): `120e3a3cd`.

Also fixed and pushed: two regressions of my own. RTTI self-relative words
(`120e3a3cd`) and a soname interned inside `.dynstr` (`1cdb560f4`).

**Landed:**
- x86-64 executables (`b05b7bb0a`).
- ESP-IDF objects, both ELF32 writers (`c44fa2642`).

**test-core after all of the above:** runs 1 and 2 stopped at `synthclob26`
(fixed) and at `test_object_value_constructor_error`. The second is a STALE
row: efe06a903 deliberately allowed constructors in `object`. Its fix is on origin as
`cdf0c0539` (frankb-56). I first quoted it by its pre-rebase ghost sha, which
was wrong. Run 3 used a scratch Makefile
copy with only that row dropped, and was past both earlier stops with no
failures at the time of writing. Its verdict is appended below if it finished
while this seat was still live. That run measures the same row set origin has
had since `cdf0c0539`. If no verdict follows, it did not finish while this seat
was live.

**Next step (cold-seat resume), in order of value:**
1. **Hosted aarch64 / i386 / arm32 executables.** The layout is generic:
   `RoLayoutPrepare(wanted, page)`, `DataRemap`, `RoPermuteData`. Each of
   these writers needs what the two x86-64 `writeELF` copies got: call
   `RoLayoutPrepare` after `PrepareDynamicData`; add a program header when
   `RoSplitActive`, which moves `codeOffset`; route every data address through
   `DataVA` / `DataFilePos`; write `DataFileLen` bytes; call `RoPermuteData`
   after the fixups; and loop `DataRelFix` through `DataRemap`. Grep
   `RoSplitActive` in `writeELF` for the full list. Verify with the
   `test_ro_data_literal_store` rows under qemu: faults when split, runs with
   `--no-ro-data`.
2. **Then RTTI / VMT / dispatch tables / float constants**, each only after its
   own measurement that it is never written. RTTI emission is frankb-56's
   (see "whether a blob is emitted is theirs, where a survivor lives is
   ours"). Hazard for any new RO range: a contiguous RW structure is CUT if a
   literal is interned between its first and last byte. Guard with an
   `RoRangeCount` snapshot plus `ErrorNoPos`, as `PrepareDynamicData` does.
3. **ESP caveat to keep:** only DIRECT references from `iram;` code keep a
   literal in `.data` (`ObjRoKeepIramLiteralsWritable`). A read through a
   pointer is not seen. Any future read-only VMT/RTTI would need the same
   thought for iram methods.

**Run-3 verdict (appended 14:10):** `rc=2` at the `--threadsafe` self-host
fixedpoint row: `pascal26-threadsafe-self` and `-next` differ at byte 217.
Every row before it passed, including both earlier stop points. That red is
the MID-RUN PULL, not a defect. Parking synced 9 files of
`compiler/thread_emit.inc`, `lib/rtl/palthread.pas` and others while the run
was going, so a binary built before the pull compiled sources from after it,
which gives two valid fixedpoints. Run alone on the settled tree
(f89dcf573, rebuilt), the same row gives `cmp` SAME. Rows after that one did
not run. Mixed-tree evidence, as stated above: this is not a clean run of any
single sha.

## 2026-09-19 (frankH) — aarch64 hosted: landed

aarch64 goes through the same 64-bit `writeELF` as x86-64. Every one of its
data references is an absolute literal word, a 4-byte global or a GOT slot, and
each already resolves through `DataVA`. So the change is the `wanted` condition
in both `writeELF` copies. The page shift is `ElfSegAlign` (64 KiB on aarch64).
`test-aarch64` GREEN in full; 119 of 120 sampled test binaries carry the R-only
PT_LOAD. New rows at the top of `test-aarch64`: the probe faults (rc 139) with
the split and runs with `--no-ro-data`. Next: i386/arm32, which use the single
`writeELF32`; see the recipe in the park section above.

## 2026-09-19 (frankH) — i386 and arm32 hosted: landed

`writeELF32` got what `writeELF` has, minus nothing:
- `RoLayoutPrepare` for i386/arm32 and never the bare ESP image;
- one more phdr, so `codeOffset` += 32;
- `DataVA` for data and data-resident globals, `DataPtrFix`, GOT call sites
  and `PatchDynamicData32`;
- a `DataRelFix` loop, which this writer never had because nothing moved
  before;
- `RoPermuteData` after the patches;
- R + RW PT_LOADs, with INTERP/DYNAMIC through `DataFilePos`/`DataVA`;
- `DataFileLen` written;
- both `DbgWriteShdrTable32` copies name only the RW part as `.data`.

Verified:
- `test-i386` and `test-arm32` GREEN in full.
- 233/234 i386 and 201/202 arm32 tier binaries carry the R-only PT_LOAD,
  3 dynamic on each.
- New fault/control rows at the top of both tiers.
- `-g` probed by hand: `.data` shdr equals the RW segment on both, readelf
  clean, and `-g -O2` faults as expected. `-g` alone lowers `-O`, so the
  literal is copied before the store; that is the same on x86-64.

**Step 1 of the park section is DONE: every hosted target has the segment.**
Next is step 2, RTTI/VMT/tables after measurement. It needs coordination with
frankb-56, who owns RTTI emission.

## 2026-09-19 (frankH) — RTTI/VMT: measured under --ro-rtti, nothing writes them on the paths test-core runs

`--ro-rtti` (48b75b34b, EXPERIMENTAL, off by default) marks each class RTTI
header (EmitRTTI Pass 1 reservation) and each Pascal VMT with its two backlink
words (both pasparser VMT sites, declared classes and the builtin TObject)
read-only, at emission.

Positive control, `test_ro_rtti_write` (in test-core): a store into a VMT slot
and one into an RTTI header, each reached through an INSTANCE (VMT pointer, then
the backlink at VMT-8), fault rc=139 with the flag and land without it.

Sweep: the flag defaulted on (an uncommitted one-line edit, reverted after),
rebuilt (converged, 2 rounds, `b8ea1fdefb92`, tree 48b75b34b, which carries
frankb-56's registry gate 5bde993c5), `testmgr --tier native --job 'test-core*'
--jobs 4`: **2355/2356 pass**. The one FAIL is `test_ro_rtti_write-control`, as
predicted: with the flag forced on, its "without the flag" leg faults too. A
first attempt was killed by the harness's low-memory guard after 42 jobs and
measured nothing.

What the green covers: 1550 Pascal subjects; 460 declare a class, 110 use
virtual/override, 28 publish, 48 use typinfo-style property access, and four
exercise streaming or LFM for real (`test_streaming`, `test_streaming_enumset`,
`test_lfm`, `test_wildcard_lfm`).

**What it does NOT cover. A clean run says nothing writes these spans on the
paths that EXECUTED; a fault that never happened is not proof of safety.**
- The pcl widgets and the demos: `lib-test`/`make demos` were not run under
  the flag, and they are the heaviest reflective consumers.
- Streaming and LFM beyond those four fixtures.
- Code reached only by reflection at run time, beyond the 48 subjects above.
- NilPy's VMTs (`pyparser.inc`), which are not marked at all.
- Published property/method arrays, IMTs, enum RTTI and layout RTTI, which
  are not marked.
- The RTTI registry table. It is excluded by SCOPE, not by any reason it would
  fault: AddDataPtrFix patches the file image, as it does for the headers that
  ARE marked. Whether anything writes it at run time is unmeasured.
- The self-host with the flag on converged, but compiler.pas declares no
  classes, so it exercises only TObject's two spans. Weak evidence.

Next, before --ro-rtti can become the default: lib-test and the pcl demos
under it.

## 2026-09-19 (frankH) — lib-test under --ro-rtti: clean

`make -i lib-test PXX_STABLE=<HEAD + RoRtti defaulted on>` (compiler sha
`f4bc5ebb9b6e`, tree 46381a9e9; `-i` because the recipe otherwise stops at its
first red and leaves the rest unmeasured) ran to the end. There were no
segfaults, and the only failures were the two rows of `lib_mimic_xmlreader`.
Those are the pre-existing `regression-lib-test-lib-mimic-xml-sax-xmlreader`
(a tuple repr printed with quotes): 24/25 with the flag, without it, and on the
pinned compiler alike. lib-test skipped synapse-ssl and reportlab-diff.

What this adds: the lib/rtl suites, the NilPy library rows, and the tk facade
RUN under xvfb. What it still does not add: **a pcl widget program RUNNING.**
lib-test only COMPILES lib/pcl (lib_units_compile.py), and `make demos` only
builds. So the pcl gap in the section above stands, and it is now the one
thing between this flag and the default: run one reflective pcl GUI program
(published properties, LFM) under xvfb with the flag, plus its flag-off control.

