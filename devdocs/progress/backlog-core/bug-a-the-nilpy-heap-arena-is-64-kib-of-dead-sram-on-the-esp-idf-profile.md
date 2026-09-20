---
slug: bug-a-the-nilpy-heap-arena-is-64-kib-of-dead-sram-on-the-esp-idf-profile
track: A
prio: 65
type: bug
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "Every NilPy program built for --platform=esp reserves SocNilPyArenaSize = 64 KiB of BSS for a heap arena that nothing on that profile allocates from. Under PXX_ESP_IDF the pxx heap IS IDF's heap -- PXXAlloc/PXXFree are calloc/free -- and builtinheap.pas's native allocator, the ONLY reader of HeapPtr/HeapEnd, lives in the {$else} arm and is not compiled. Measured: 64 KiB is 31% of the 211,296 B free DRAM pool on a C3, and 52% of our own 125,832 B of SRAM. Attribution is a DIFFERENTIAL, not arithmetic on a matching number -- withHeapArena is true only for pyparser, so a Pascal program on identical target and flags reports 650 B of unattributed bss against NilPy's 66,237 -- which matters because SocNilPyArenaSize and the RTL's EspArena/HEAP_ARENA are both 64 KiB and a grep reaches the wrong one first. AND THE ARM WHERE THE ARENA WOULD BE LIVE IS ITSELF BROKEN: --esp-profile=bare cannot compile ANY NilPy program, not even `print(1)` ([[bug-a-the-bare-esp-profile-cannot-compile-any-nilpy-program]]), so today this constant costs 64 KiB on the one profile that works and delivers nothing on the one where it would matter. THE SENSITIVITY CONTROL IS UNAVAILABLE and that is stated rather than papered over: shrinking the arena to 16 bytes leaves the IDF demo passing qemu-assert, which is CONSISTENT with a dead arena and is not proof on its own, because the profile where a 16-byte arena must fail loudly is the broken one."
---

# The NilPy heap arena is 64 KiB of dead SRAM on the ESP-IDF profile

Found 2026-09-20 categorising `.bss` under
[[umbrella-an-esp32-image-is-as-small-as-it-can-be]], on the owner's axis:
*"SRAM here is most relevant."* If this holds it is **larger than every named
item on the read-only-segment REMAINING list put together** — those measure at
32 bytes on a NilPy image.

## The reservation

`frontend_prologue.inc`:

```pascal
if EspBareBoot or (TargetPlatform = PLATFORM_ESP) then
begin
  BSS_HEAP_ARENA := BSSSize;
  Inc(BSSSize, SocNilPyArenaSize(TargetSoc));   { 64 * 1024 }
end;
```

The `or (TargetPlatform = PLATFORM_ESP)` arm was added deliberately — the
comment says an IDF object has no kernel to mmap from either, and bare-only
left every NilPy program refused under IDF with *"a heap arena needs mmap"*.
**That fixed a real refusal. The question here is whether the arena it reserves
is ever ALLOCATED FROM on that profile.**

## Why it looks dead

`builtinheap.pas` splits the allocator on `PXX_ESP_IDF`:

- **`{$ifdef PXX_ESP_IDF}`** — `PXXAlloc`/`PXXFree` are `calloc`/`free`
  externals, resolved to newlib/heap_caps at IDF link time. The header says so:
  *"the bare-metal static arena is both tiny and redundant next to the SoC's
  real heap."*
- **`{$else}`** — the native allocator, and it is the **only** code that reads
  `HeapPtr`/`HeapEnd`, the two globals `EmitBareHeapArenaInit` points at the
  arena.

Under IDF that `{$else}` arm is not compiled, so nothing can allocate from the
arena. Corroborating and independent: after `--dce` our object relocates
against exactly six externals and **`calloc` and `free` are two of them**.

## Evidence, and what is missing from it

| | |
| --- | --- |
| attribution of the 66,237 B | **differential**: Pascal 650 B vs NilPy 66,237 B, same target and flags |
| direct confirmation of the size | arena at 4096 → `bss` 89,352 → 27,912, exactly −61,440 |
| arena shrunk to 16 bytes | IDF demo still passes `qemu-assert`, one boot, output == expected |
| **sensitivity control** | **UNAVAILABLE — see below** |

**The control that would settle it cannot be run.** A 16-byte arena passing
proves the arena is dead *only if* a live 16-byte arena would have failed
loudly. The profile where the arena IS the heap is `--esp-profile=bare`, and
that profile **cannot compile a NilPy program at all** — `print(1)` answers
`undefined variable (PXXVarBinOp)`. So the probe's own failure mode is
undemonstrated, and the claim rests on the structural fact (the `{$else}` arm
is not compiled) with the 16-byte run as corroboration rather than proof.

**Do not upgrade the 16-byte pass to proof without that control.** A pass from
an instrument that has never been shown to fail is the thing this repo files
tickets about.

## What to do, in order

1. **Establish the control.** Either fix
   [[bug-a-the-bare-esp-profile-cannot-compile-any-nilpy-program]] and watch a
   16-byte arena die there, or add a temporary `PXXAlloc` path under IDF that
   uses the arena and watch it die. Until one of those runs, this is a strong
   hypothesis.
2. **Then gate the reservation on the profile**, not on the platform:
   `EspBareBoot` needs it; `PLATFORM_ESP and not bare` does not. Note the
   spelling hazard CLAUDE.md records — `PXX_ESP_IDF` is the *compiler-side*
   define and `EspBareBoot` the flag; the two read alike and differ on exactly
   one configuration.
3. **Re-measure the pool**, which should rise by ~64 KiB from 211,296.

## What would make this WRONG

If anything on the IDF profile reaches `HeapMmap` or the native `PXXAlloc` —
a path the `{$ifdef}` split does not cover, or an RTL unit compiled without
`PXX_ESP_IDF` — then the arena is live and removing it is a crash. **Grep for
readers of `HeapPtr` and `HeapEnd` outside the `{$else}` arm before changing
anything**, and note `HeapPtr`/`HeapEnd`/`HeapLow`/`HeapHigh`/`HeapLiveBytes`
are all still declared and still in `.bss` under IDF, so their presence proves
nothing either way.
