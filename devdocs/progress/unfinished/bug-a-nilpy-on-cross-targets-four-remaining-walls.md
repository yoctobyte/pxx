---
track: A
prio: 85
type: bug
blocked-by: []
summary: "ARM32 NOW WORKS — measured 2026-08-31, it builds AND runs a class-heavy .npy correctly under qemu-arm, so the SIGILL below is fixed and this ticket is no longer 'no cross target'. The other walls, re-measured at that date and NOT what the table below says: i386 `symbol kind not supported yet (load)`, aarch64 `indirect call with more than 8 parameters` (ir_codegen_aarch64.inc:3309 — one of SIX separate >8 refusals on that backend), riscv32/xtensa BARE METAL: the heap-arena wall is CLEARED (2026-09-17) — all three of esp32s3/esp32c6/esp32c3 now reach a NEW and deeper wall, `undefined variable (PXXVarBinOp)` in builtin.pas, which is bare metal pulling no `builtin` unit at all (espassert.pas:24 documents it: that unit does not compile for ESP). HOSTED riscv32/xtensa still refuse — EmitMmapArena has no arm for either, which is a different fix. wasm32 `undefined variable (SYS_openat)`. Five walls, not four. ~53 .npy tests stay cross-blind on everything but arm32."
status: unfinished
owner: claude-A
---

# NilPy on cross targets: four remaining walls

- **Track A** (the i386 / arm32 / aarch64 / riscv32 backends). NOT Track N —
  the NilPy frontend is fine; these are backend gaps that happen to be reachable
  only through the NilPy runtime's Pascal source (`compiler/builtin/pyeval.pas`
  and friends).
- Opened 2026-08-21, immediately after
  `bug-a-a-string-tagged-address-binop-walls-off-nilpy-on-three-targets` moved
  the wall from "refuses" to these four.

## The probe

```sh
cat > /tmp/v1.npy <<'PY'
def main():
    a = 1
    b = 2
    print(a + b)
main()
PY
for t in i386 arm32 aarch64 riscv32; do
  ./compiler/pascal26 --target=$t /tmp/v1.npy /tmp/v1_$t && tools/run_target.sh $t /tmp/v1_$t
done
```

## Re-measured 2026-08-31 (frankS) — read this table, not the 2026-08-21 one

One command per target, `print(1+1)` as the source, at `96f92002f`:

| target | wall, today |
| --- | --- |
| **arm32** | **NONE — it builds and RUNS.** `test_nilpy_object_in_variant_slot_survives_churn.npy` prints CPython's own answer under `qemu-arm`, and RSS is flat over 400k constructions. The SIGILL below is fixed. |
| **i386** | `target i386: symbol kind not supported yet (load)` — unchanged |
| **aarch64** | `target aarch64: indirect call with more than 8 parameters not supported` (ir_codegen_aarch64.inc:3309). NOT the "aggregate result" message below; the wall moved. It is one of SIX `> 8` refusals on that backend — constructor, external, variadic external, cdecl indirect, indirect, virtual — i.e. aarch64 has no stack-argument passing for five of six call kinds, and the direct call is the only one that does. That is one mechanism, refused six times. |
| **riscv32** | `a heap arena needs mmap, which this profile has not` — unchanged |
| **xtensa** | same mmap wall (not in the 2026-08-21 table at all) |
| **wasm32** | `undefined variable (SYS_openat)` (not in the table either) |

Cost of the aarch64 wall, so it is not underrated: it is what makes the aarch64
half of `feature-nilpy-object-reclamation`'s item 4 unreachable — the inline
`EmitVariantClearA64`/`RetainA64` object arms cannot be tested by any NilPy
program, because no NilPy program compiles for that target.

## Current walls (2026-08-21, at the sha that resolved the binop gate)

| target | wall |
| --- | --- |
| **arm32** | **builds**, then `qemu: uncaught target signal 4 (Illegal instruction)` — **diagnosed, see below**. |
| **i386** | `target i386: symbol kind not supported yet (load)` |
| **aarch64** | `target aarch64: aggregate result with more than 8 params not supported` |
| **riscv32** | `mmap not supported on bare-metal target` — riscv32 is a bare-metal profile, so the NilPy runtime's heap needs the same treatment the ESP profile got. Possibly the odd one out and not worth chasing with the other three. |

## The arm32 SIGILL is not an arm32 bug — the NilPy driver emits an x86-64 entry stub

Measured 2026-08-21. The ELF header says ARM; the bytes at the entry point are
**x86-64**:

```
h_arm32  (Pascal hello)  @0x74: 00109fe5 000000ea ... ldr r1,[pc] / b .+8   <- ARM
v1_arm32 (NilPy hello)   @0x74: 48892425 60502b08 48be...              <- mov %rsp,0x82b5060
                                                                          movabs $0x10000000,%rsi
```

`compiler/pyparser.inc:~34622` writes the NilPy program prologue as raw x86-64
bytes with **no target dispatch at all**:

```pascal
EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
MovRsiImm(HEAP_ARENA_SIZE);
EmitMmapArena;
EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
...
EmitB($E9); jmpPatch := CodeLen; EmitI32(0);          { jmp main }
```

The Pascal driver has the per-target version of exactly this
(`pasparser_prog.inc:929-1045` — i386 / arm32 / aarch64 / xtensa / riscv32 /
x86-64 arms, each saving the initial sp and branching to the main body). The
NilPy driver never got it. Neither did the other frontends: `fparser.inc:357`,
`bparser.inc:689`, `aparser.inc:361`, `gparser.inc:373`, `lparser.inc:305`,
`wparser.inc:220`, `eparser.inc:533` all emit the same `48 89 24 25` blind.

`EmitMmapArena` (`emit.inc:163`) is the same shape one level down: it *Errors*
for xtensa and riscv32 and then **silently emits x86-64** for i386, arm32 and
aarch64. A refusal for two targets and a lie for three.

So the fix is not an arm32 codegen feature. It is the shared-entry-stub
extraction the Pascal driver's arms are already the reference for:

1. lift `pasparser_prog.inc`'s per-target entry stub into one
   `EmitEntryStubForTarget(var jmpPatch)` next to `EmitIoLockStubsForTarget`
   (which exists for precisely this reason — read the comment at
   `pasparser_prog.inc:1080`: *"The per-arch choice used to be spelled out here,
   in the Pascal driver only, which is precisely why the other eight frontends
   shipped without it."*);
2. give `EmitMmapArena` real arms (or an `Error`) for i386/arm32/aarch64 so it
   can never lie again;
3. call both from the NilPy driver, then from the other seven.

That is one change that unblocks arm32 and moves i386/aarch64 to their next
wall, instead of three per-target patches. Rank it as the first step here.

Take the rest one at a time; each is an ordinary backend gap with the two-line
probe above and the playbook in `devdocs/dev/debugging-playbook.md`.

## Why it matters

~53 `.npy` tests exist and none of them has ever run on a cross target. They
show up in any cross differential as BUILDFAILs and get misread as record or
variant gaps — that is exactly how this was found. Every one of the four walls
is worth a separate ticket once someone starts; this one is the index.

## Gate

Per wall: the probe builds and runs on that target; self-host fixedpoint +
`tools/gate.sh quick`.

## Progress — arm32 is GREEN (2026-08-21)

Three defects, all the same disease, all fixed together:

1. **`EmitProgramEntryForTarget`** (new, `ir_codegen.inc`, next to
   `EmitIoLockStubsForTarget`) — the entry stub's six per-arch arms, lifted out
   of the Pascal driver verbatim, plus an optional mmap heap arena for the NilPy
   allocator model. The Pascal driver passes `False`, NilPy `True`.
2. **`PatchProgramEntryJump`** (new, same place) — the *other* half. Missed on
   the first pass: the NilPy driver kept its own
   `Patch32(jmpPatch, CodeLen - (jmpPatch + 4))`, which wrote a raw byte offset
   over an ARM branch word. The stub was correct and the program SIGILLed four
   instructions later. The two halves are one thing and now live together.
3. **`EmitMmapArena(len)`** (`emit.inc`) — real i386 / arm32 / aarch64 syscall
   arms (mmap2(192) / mmap2(192) / mmap(222)). It used to Error for xtensa and
   riscv32 and silently emit x86-64 for the other three. Length is a parameter
   now, because every ABI wants it in a different register and hiding that in
   the caller is what made the lie possible.
4. **`EmitAnsiStringRuntime` is x86-64 machine code** and the NilPy driver
   called it unguarded — the Pascal and C drivers both have
   `and (TargetArch = TARGET_X86_64)`. The blob was never executed; its length
   is not a multiple of 4, so it shifted every ARM instruction after it two
   bytes out of alignment and the first real proc decoded as garbage. That was
   the second SIGILL.

### Measured

- `def main(): print(1+2)` on arm32: **runs, prints 3**. First NilPy program
  ever to execute on a cross target.
- 60-test `.npy` differential vs the native oracle on arm32:
  **8 match, 34 BUILDFAIL, 10 run-but-wrong** (8 of the 60 fail natively too and
  are excluded). Was 0 match / 52 BUILDFAIL.
- **All 34 remaining BUILDFAILs are one wall**:
  `target arm32: IR op not yet supported: zero_sym`. Filed separately.
- The Pascal driver's arm32 output is **byte-identical** across the extraction
  (`cmp` on a hello-world arm32 binary built before and after) — the lift is a
  pure refactor on that side.
- Self-host fixedpoint + `tools/gate.sh quick` GREEN.

### Still open

| target | wall |
| --- | --- |
| arm32 | `IR op not yet supported: zero_sym` (34 of 52) — the one thing between here and broad NilPy-on-arm32 |
| i386 | `symbol kind not supported yet (load)` |
| aarch64 | `aggregate result with more than 8 params not supported` |
| riscv32 | bare-metal profile has no mmap |

The other eight frontend drivers (`fparser`, `bparser`, `aparser`, `gparser`,
`lparser`, `wparser`, `eparser`, `rparser`, `zparser`) still open-code an
x86-64 entry stub. They were NOT converted here: each has a different shape
(some emit no jump at all, some `call main` with their own exit tail), they are
all x86-64-only frontends today, and a blind sweep would be churn without a
gate to catch it. The C driver has its own per-target case already. When one of
those frontends grows a cross target, `EmitProgramEntryForTarget` is what it
should call.

## Progress — `zero_sym`, and the wall behind it (2026-08-21)

`IR_ZERO_SYM` existed on x86-64 and i386 only; arm32, aarch64 and riscv32 all
raised `IR op not yet supported: zero_sym`. Added to all three (pointer-width
store for a scalar / dyn-array handle, `PXXMemZero` for a managed span), cloned
from the two arms that had it.

- 60-test `.npy` differential on arm32: **broke=0**, every one of the 34
  BUILDFAILs now BUILDS. Match went 8 -> 9.
- 53-test dyn-array + interface differential over all four cross targets:
  **broke=0 fixed=0** — the new arms never fire for Pascal, which zero-inits
  through the parser's prologue pass instead.
- Self-host fixedpoint + `tools/gate.sh quick` GREEN.

### The wall behind it: NilPy's PROC PROLOGUE is raw x86-64

Of the 52 runnable `.npy` tests on arm32: **9 match, 1 BUILDFAIL, 42 wrong — and
38 of those 42 are `rc=-4` (SIGILL) with no output at all.** Same signature as
before: `qemu-arm -d in_asm` shows the instruction stream two bytes out of
alignment, i.e. an odd-length x86-64 blob spliced into the ARM code.

The source this time is the NilPy function prologue. `PyEmitParamSpills`
(`pyparser.inc:17433`) and `PyInitVariantLocals` (`pyparser.inc:1924`) emit raw
x86-64 — `mov rax, rdi` (3 bytes, hence the 2-byte drift), `mov [rbp+off], rax`,
`mov qword [rbp+off], 0` — and are called unguarded from **three** proc-emission
sites (`pyparser.inc:28113`, `28561`, `31624`). `v1.npy` survives only because
`main()` takes no parameters.

This is NOT a small guard like the last three. The Pascal driver does not have a
shared param-spill to call: `pasparser_proc.inc:1842` onward is several hundred
lines of per-target spill logic living *inside the driver*, which is exactly
what **`refactor-a-the-missing-layer-between-frontends-and-backends`** (prio 50,
Track A) exists to fix. NilPy-on-cross needs that layer; bolting a fourth
per-target copy into `pyparser.inc` would be the wrong fix and would make the
refactor harder.

**Parked here.** The campaign's next step is the refactor ticket, not another
patch in this one.


## RE-RANKED 40 -> 85, 2026-09-17, on the owner's ESP refocus

**Not on merit — on POSITION.** The owner turned the shop back to the ESP32 the
same day Adafruit shipped CircuitPython "Turbo": host-compiled `@native`/`@viper`
functions delivered to the board as `.mpy`, with a 2-3 KB loader and **no
on-board compiler**, `-march` values including `xtensa`, `xtensawin` and
`rv32imc`, verified on ESP32-S2/S3 and ESP32-C5.

**What that establishes is an audience, not a competitor.** Turbo accelerates
functions inside a running VM; the interpreter is still there. Nobody ships
*"your Python program IS the firmware"* — one web search, so read that as
consistent-with rather than proven, but it matches the landscape (Nuitka and
Cython need CPython, Codon/mypyc/Shed Skin are desktop, Zerynth was a VM and is
gone). **That claim is ours to make and we cannot make it yet, and THIS TICKET
IS WHY.** Measured 2026-09-17 at `578b158524a5`, a 20-line Mandelbrot `.npy`
that runs correctly on the host:

```
$ pascal26 --target=esp32s3 mandel.npy out
pascal26:1: error: target xtensa: a heap arena needs mmap, which bare metal has not
$ pascal26 --target=esp32c6 mandel.npy out
pascal26:1: error: target riscv32: a heap arena needs mmap, which this profile has not
```

**ONE WALL, BOTH ESP ARCHITECTURES.** The summary above counts five walls across
six targets and that is right, but they are not equally placed: the mmap arena is
the *only* one standing between us and the ESP pair, and xtensa is the primary
ESP target while riscv32 is the other one. i386, aarch64 and wasm32 are real and
are not on this path — **do not bundle them into an ESP estimate.**

**The claim to protect while this is open, because the two are not the same
sentence:** *"pxx runs on ESP32"* is TRUE today (Pascal reaches xtensa). *"pxx
compiles Python to ESP32"* is FALSE today. Neither goes into public copy in the
other's place.

**And there is now an outside benchmark to be measured against**, which we have
never had for ESP: Turbo's published Mandelbrot inner loop, twelve boards,
ESP32-C5 at 172 ms and 44x over float bytecode. Once this wall falls, running
that same loop under pxx on an S3 and a C5 produces the first pxx number an
outsider can compare — which is exactly what Track O's PROMISE gate asks for:
delivered value, measured, not opportunity inferred.

**Ranked at 85, not 90:** it is one wall with a named mechanism, not a research
question, and nothing is blocked on it today except a claim we are not making.

## 2026-09-17 (frankS) — the bare-metal heap arena, and what it exposed

**The mmap wall is gone for BARE METAL on both ISAs.** It was never really an
mmap problem: bare metal has no kernel to ask, so the arena does not need to be
*obtained* at all — it needs to BE part of the image. It is BSS now.

| target | before | after |
| --- | --- | --- |
| esp32s3 (xtensa, bare) | `a heap arena needs mmap, which bare metal has not` | `undefined variable (PXXVarBinOp)` |
| esp32c6 (riscv32, bare) | `a heap arena needs mmap, which this profile has not` | `undefined variable (PXXVarBinOp)` |
| esp32c3 (riscv32, bare) | same | `undefined variable (PXXVarBinOp)` |
| riscv32 (hosted linux) | same | **still refuses, deliberately** |
| xtensa (hosted) | same | **still refuses, deliberately** |

### What was actually built

`BSS_HEAP_ARENA`, reserved beside the four slots that point into it, sized by a
new SoC capability `SocBareArenaSize` (64 KiB today, uniform across the parts,
and a capability rather than a seventh top-level constant because what it is
really derived from is the region between `SocIramBase` and the stack top).
`EmitBareHeapArenaInit` publishes `BSS_HEAP_PTR`/`BSS_HEAP_END` — the same two
stores the hosted path does after `EmitMmapArena`, minus the syscall.

**No new relocation kind was needed, which is why this is 151 lines.** The stub
is emitted during codegen, long before the ELF writer knows `bssBase` — but
`EmitGlobRef(off)` already records a fixup patched with `bssBase + off`. So
`EmitGlobRef(BSS_HEAP_ARENA + size)` *is* the end pointer, with no add
instruction at all, which also sidesteps both ISAs' 12-bit immediate limits.
And BSS is memsz-only (`filesz = codeOffset + CodeLen + DataLen`), so a 64 KiB
arena costs nothing in the file.

**ONE helper, not two.** The two refusals were two spellings of one refusal
("which bare metal has not" / "which this profile has not") — the
normalise-dont-special-case shape. The old xtensa message also fired on the
HOSTED arm while telling the reader it was bare metal; both messages now name
which profile they mean.

### Verified rather than believed

The stub is not reachable by any program yet (see below), so it was forced onto
the bare Pascal path temporarily and the emitted bytes decoded, then reverted —
the compiler is byte-identical (`bb4f3f186fab`) before and after the revert.

    riscv32   &arena 0x4038ec98   &arena+size 0x4039ec98   delta 65536  OK
              &HEAP_PTR 0x4038ec78  &HEAP_END 0x4038ec80   delta 8      OK
              both stores 0x00532023 = sw t0,0(t1)                      OK
    xtensa    0x40383ea8 -> 0x40393ea8                      delta 65536  OK
              0x40383e88 -> 0x40383e90                      delta 8      OK

BSS grew by exactly 65536 on both; code by 72 bytes (riscv32: 4 address loads of
16 + 2 stores of 4) and 56 (xtensa). `gate.sh quick` GREEN with **FPC seed canary
PASS, not SKIP** — which matters here because this adds a forward in
`frontend_forwards.inc` with its body in `ir_codegen.inc`, exactly the
declaration-order class that canary is the only instrument for.

`CheckBareImageFitsSram` is the guard that makes a compile-time-chosen arena size
safe: the size is picked before any code length exists, so it is a REQUEST, and
the writer refuses the build if image+data+bss+a minimum stack does not fit.
Positive control run (temporarily raising the stack reserve): it fires with the
overshoot in bytes. Its first draft named the arena on a Pascal build that had
none — fixed to report the arena only when one was reserved.

### INERT UNTIL THE NEXT PIN

`2b2ec3fee` landed AFTER pin v411 (`8d9d69bdc`), so **anything building with
`$(PXX_STABLE)` still gets the old refusal.** Track B/E demos, `lib-test` and any
`.npy` built against the pinned compiler see `a heap arena needs mmap` until the
next pin carries this. Not a reason to pin again — v411 is hours old and pins are
cadence, not releases — but it is the reason a bare-metal ESP measurement taken
with the pinned compiler will disagree with one taken at HEAD, and CLAUDE.md's
two dated casualties of this class were a fix inert for a MONTH and one landing
three hours after a pin.

### THE NEXT WALL IS MUCH BIGGER THAN THIS ONE, and it was hidden behind it

`PXXVarBinOp` is not a small gap. `--esp-profile=bare` pulls **no `builtin` unit
at all**, deliberately — `espassert.pas:24` says `uses builtin` under that profile
"really does fail", measured, on `PXXVarBinOp` and `PxxSciDigits17`, both in
companion units bare does not get. NilPy's driver requires `builtin`. So
NilPy-on-bare is blocked on making `builtin` compile for ESP, which is a
different and far larger job than this was.

This is the first-failure pattern the umbrella rule warns about, arriving inside
one ticket: the arena wall was the only thing anyone could see, and clearing it
revealed that it was never the expensive one. **No NilPy program runs on ESP bare
metal yet, and this change does not claim one does** — what it claims is that the
arena is no longer why.

Scope held deliberately to the arena wall: i386, aarch64 and wasm32 are
untouched and are not part of any ESP estimate.

### Adjacent, flagged, NOT chased

- `ESP_BARE_STACK_TOP` is one constant whose own comment claims validity only
  for C3 and S3, and it is used for all six SoCs.
- `SocIramBase` branches only xtensa-vs-not, so C6 inherits C3's base.
- The repo records no C6 memory map at all.

These are why `SocBareArenaSize` is a capability: when a part with a different
map is measured, the divergence belongs there and not in a new constant.

