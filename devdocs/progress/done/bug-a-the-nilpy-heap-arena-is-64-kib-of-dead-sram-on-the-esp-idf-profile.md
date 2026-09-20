---
slug: bug-a-the-nilpy-heap-arena-is-64-kib-of-dead-sram-on-the-esp-idf-profile
track: A
prio: 65
type: bug
status: done
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "Every NilPy program built for --platform=esp reserves SocNilPyArenaSize = 64 KiB of BSS for a heap arena that nothing on that profile allocates from. Under PXX_ESP_IDF the pxx heap IS IDF's heap -- PXXAlloc/PXXFree are calloc/free -- and builtinheap.pas's native allocator, the ONLY reader of HeapPtr/HeapEnd, lives in the {$else} arm and is not compiled. Measured: 64 KiB is 31% of the 211,296 B free DRAM pool on a C3, and 52% of our own 125,832 B of SRAM. Attribution is a DIFFERENTIAL, not arithmetic on a matching number -- withHeapArena is true only for pyparser, so a Pascal program on identical target and flags reports 650 B of unattributed bss against NilPy's 66,237 -- which matters because SocNilPyArenaSize and the RTL's EspArena/HEAP_ARENA are both 64 KiB and a grep reaches the wrong one first. AND THE ARM WHERE THE ARENA WOULD BE LIVE IS ITSELF BROKEN: --esp-profile=bare cannot compile ANY NilPy program, not even `print(1)` ([[bug-a-the-bare-esp-profile-cannot-compile-any-nilpy-program]]), so today this constant costs 64 KiB on the one profile that works and delivers nothing on the one where it would matter. PROVED DEAD 2026-09-20 by a DIFFERENT control than the one that was missing, and the runtime sensitivity test is no longer needed: HeapMmap -- the arena-refill call PXXAlloc's native arm makes, and the only route by which HeapPtr/HeapEnd are ever read -- is DECLARED ABOVE the {$ifdef PXX_ESP_IDF} split, so it is compiled on every profile and its SURVIVAL UNDER --dce is a reachability readout with both arms available on the working profile. On the IDF demo object it is PRESENT under --no-dce and DROPPED under --dce, so nothing calls it. "}
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

## PROVED DEAD, 2026-09-20 — and the control came from reachability, not from survival

The sensitivity control this ticket said was unavailable **is still
unavailable**, and it is no longer what settles the question.

**What was wrong with the plan.** Every probe considered — shrink the arena,
fill it with a pattern, watch `HeapPtr` — asks whether the arena SURVIVES.
That class of readout has no positive control on the only profile that
compiles, for the reason this ticket already gave: if nothing allocates from
the arena on either arm, it survives either way. Chasing a better survival
probe was chasing a better instrument for the wrong question.

**The question that does have a control is REACHABILITY.** `HeapPtr`/`HeapEnd`
have exactly one runtime reader in the tree — `PXXAlloc`'s arena-refill block,
`builtinheap.pas:1737-1754`, which is inside the native `{$else}` arm. That
block's distinguishing call is `HeapMmap`, and `HeapMmap` is **declared at line
1272, ABOVE the `{$ifdef PXX_ESP_IDF}` split at 1391**. So it is compiled on
every profile, it is dead-strippable, and whether `--dce` removes it is a
direct statement about whether anything calls it.

Both arms, one program (`examples/esp32/nilpy-c3/main/main.npy`),
`--target=riscv32 --platform=esp --emit-obj`, compiler `f18adc62d2ac`, oracle
`readelf -sW`:

| build | `HeapMmap` | code |
| --- | --- | --- |
| `--no-dce` | **present** | 3,002,932 B |
| `--dce`    | **dropped** | 2,074,564 B |

Present when compiled, dropped when unreferenced: **the instrument moves, so it
is not a guard that cannot fail.** Nothing on the IDF profile calls the
arena-refill path, so nothing reads `HeapPtr`, so the 64 KiB is written once by
the entry stub (`EmitBareHeapArenaInit`, fired by `ir_codegen.inc:3458` whenever
`BSS_HEAP_ARENA > 0`, which includes IDF) and never read again.

**`calloc` IS NOT THE DISCRIMINATOR AND WAS NEARLY USED AS ONE.** `calloc`
appears as UND in the demo object and the IDF arm calls it — but so does the
native arm's own `{$ifdef PXX_LIBC_HEAP}` variant (`builtinheap.pas:1445`), so
its presence is consistent with either arm. A census that had stopped there
would have reported the right answer for a reason that does not hold.

**Size, with its population:** the object's `bss=89,352 B` for that program, of
which the arena is 65,536 — **73.3%**, and `--dce` does not touch it, because
DCE removes code and this is storage.

**What would retire this row:** anything that gives the IDF profile a reader of
`HeapPtr` — most plausibly routing `PXXAlloc` back onto the native allocator
over an IDF-supplied region. Re-run the two-row table above; a `--dce` build
that KEEPS `HeapMmap` means the arena is live again.

## FIXED 2026-09-20 — and the runtime confirms the reachability proof

`frontend_prologue.inc` no longer reserves the arena under `--platform=esp`;
the condition is `EspBareBoot` alone again, which is what it was before the IDF
arm was added. The IDF arm existed to keep a DIFFERENT diagnostic quiet — both
backends refused a NilPy program with *"a heap arena needs mmap"* whenever
`BSS_HEAP_ARENA = 0` — so the two guards in `ir_codegen.inc` now exclude
`PLATFORM_ESP` as well. **That diagnosis was right about the symptom and wrong
about the cure: IDF does not need an arena, it needs the mmap path not to
fire.** Reserving 64 KiB to silence a message is what the fix removes.

**Measured on the chip, two independent readouts, both moving by exactly the
arena size.** `examples/esp32/nilpy-c3`, `esp32c3`, compiler at HEAD:

| | before | after | delta |
| --- | --- | --- | --- |
| our object SRAM (`.data`+`.bss`) | 125,832 B | **60,296 B** | −65,536 (−52.1%) |
| `.bss` alone | 89,352 B | 23,816 B | −65,536 |
| free DRAM pool (chip's own `heap_init`) | 211,296 B | **276,832 B** | +65,536 |
| code | 2,074,564 B | 2,074,492 B | −72 (the init stub) |

The object's section table and the chip's `heap_init` are different
instruments — one reads our ELF, the other is FreeRTOS reporting what it found
at boot — and they agree to the byte.

**The runtime confirms it, which the reachability argument alone did not.**
`./build.sh qemu-assert` passes on **both** ISAs: `OK nilpy-c3 ... output ==
main/main.expected, one boot` and the same for `nilpy-s3`. A program whose
allocator had actually been reading `HeapPtr` would now be storing through a
null base, so booting and producing correct output is a real assertion, not a
smoke test.

**Controls, both still holding:** bare still reserves its arena
(`test_esp_bare_managed` builds, `bss=66,812`), and hosted riscv32/xtensa still
refuse with the mmap message — now reworded, since it claimed IDF reserves an
arena and IDF no longer does.

**What would retire this:** anything giving the IDF profile a real reader of
`HeapPtr` — routing `PXXAlloc` onto the native allocator over an IDF-supplied
region. The tell is `HeapMmap` surviving a `--dce` build; re-run that two-row
table first.

## Log
- 2026-09-20 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit f028632c3.
