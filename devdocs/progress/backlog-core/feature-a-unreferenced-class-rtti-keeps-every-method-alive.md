---
prio: 30
track: A
summary: "MEASURED 2026-09-18 (frankB), AND CORRECTED THE SAME DAY -- ON THE BARE PROFILE CODE IS SRAM. defs.inc's own map: qemu's esp32c3 models internal SRAM as ONE RWX region and the whole image (code+data+bss) loads at the IRAM org, so SRAM(bare) = code + data + bss. A first pass of the measurement below read data/bss as the SRAM and code as the flash -- that is the IDF shape and it is false on bare; caught by frankh-3f. Consequences: (a) `--dce` saves **54344 B of SRAM on bare** (esp32c3 131276 -> 76932, -41%; esp32s3 -36%), not zero -- it is the largest SRAM lever measured on this profile after the 64 KiB heap arena; on IDF, where .text can be flash-mapped, the same removal is a flash win and that leg is unmeasured. (b) One unreferenced class with four virtual methods costs +268 B code and +808 B data = **+1076 B, all of it SRAM on bare**; the earlier `SRAM is 3x the flash cost` line is WITHDRAWN as an IDF-shaped split applied to bare numbers. What survives: this ticket's ~3.2 KB headline is the CODE residue (method bodies held by VMT slots), while the blob's own .data bytes -- noted here from the day it opened and never quantified -- are 3x that per class, so the blob is the larger half on either profile and the only half that is SRAM at all on IDF. (c) The fleet's stated bare baseline `data=616 bss=70936, SRAM=71552` omits code and is really ~129452 at plain -O. Scales at ~128 B one-off + ~200 B per class + ~120 B per virtual method, and the 4x4 row lands 360 B UNDER that because the fixture shares method NAMES between classes -- a real program pays more, not less. On IDF the blob is .data too with .rela.data +420 and NO .rodata section at all. Ownership settled with frankh-3f: placement is his, reachability and emission are mine, and read-only placement buys ZERO SRAM on bare because moving bytes inside one RWX region changes nothing."
---

# An unreferenced class keeps every one of its methods alive

- **Type:** feature (codegen / emission size) — Track A, tag O
- **Status:** backlog — opened 2026-08-21
- **Follows:** [[feature-emission-size-dce]] (`--dce`, landed)

## What

`--dce` drops unreachable routine BODIES. It cannot drop a method, because a
method's address sits in a VMT slot (`MethodFixups`) and an address that is
taken can be called from anywhere — so every VMT slot is a root.

The VMT itself is emitted for every class the program declares, used or not. So
a `writeln('hello')` still carries, measured after `--dce`:

```
  953  PXXTIOGetInterface
  663  PXXIntfIMTOf
  555  PXXVarStrAppend
  489  PXXVarClear
  256  TInterfacedObject._Release
  134  TInterfacedObject.QueryInterface
  100  TInterfacedObject._AddRef
   44  TInterfacedObject.Destroy
```

A hello-world uses neither interfaces nor variants. ~3.2 KB of the 15.6 KB that
survives DCE is reachable only through a class nothing instantiates.

## The mechanism

Data-side reachability, one level up from the code-side pass that exists:

1. A class's RTTI blob is reachable if the program constructs it, names it in
   `is`/`as`/a class reference, or a reachable class inherits from it (the
   parent backlink is a real edge — dropping a parent breaks `is`).
2. An unreachable blob's `MethodFixups` entries stop being roots, and the
   existing code-side walk drops the bodies for free.
3. The blob's own bytes go too, which is `.data`, not `.text`.

## Watch out

- `TObject`'s blob is reached from every class — the chain has a root whether
  or not the program mentions it.
- RTTI is what `TypeInfo()`/`ClassName`/published-property access reads at
  RUNTIME with no static reference: anything that can look a class up by NAME
  (a class registry, a streaming/serialisation path) makes every registered
  class reachable, and the pass must see that or refuse.
- Same discipline as `dce.inc`: refuse rather than guess, and say why under
  `--dce-report`.

## Acceptance

`hello` loses the interface/variant residue; no behaviour change on the corpus;
`--dce-report` explains every blob it keeps. Rides the same `-O3` gate, so
`tools/optdiff.sh` sweeps it.

## Measured 2026-09-18 (frankB) — CORRECTED: on the BARE profile CODE IS SRAM, so `--dce` saves 54 KB of SRAM and the flash/SRAM split does not exist there

Measured after the owner re-ranked ESP to *"minimizing SRAM usage is prio"*.
**Profile named beside every number, because bare and IDF are different shapes
and under this re-rank that is load-bearing rather than a caveat.**

### The correction, stated first because the first version of this section got it wrong

An earlier pass of this section read `data`/`bss` as the SRAM and `code` as the
flash. **That is the IDF shape and it is false on bare.** `defs.inc`'s own map
says so: on ESP32-C3 the internal SRAM is mapped twice, qemu's esp32c3 machine
models it as ONE RWX region, and *"the whole image (code+data+bss) loads at the
IRAM org"*. So on `--esp-profile=bare`:

    SRAM(bare) = code + data + bss

Caught by frankh-3f, who owns the read-only-data placement work and pointed at
the map. Recording it because it is this repo's standing error arriving again —
a number carried from the population it was true of into one it is not. The
profile was labelled correctly and then reasoned about as if it were the other
one, which is worse than not labelling it.

**The fleet's stated bare baseline has the same gap.** `data=616 bss=70936,
SRAM = 71,552` omits code; the same build carries 57,900 B of code at plain
`-O`, so the real figure is ~129,452.

### `--dce` on the BARE profile saves 54 KB of SRAM — not zero

`test/test_esp_bare.pas`, `--esp-profile=bare`:

| target | code | data | bss | **SRAM = all three** |
| --- | --- | --- | --- | --- |
| esp32c3 plain | 59664 | 672 | 70940 | **131276** |
| esp32c3 `--dce` | 5320 | 672 | 70940 | **76932**  (−54344, −41%) |
| esp32s3 plain | 47924 | 672 | 70940 | **119536** |
| esp32s3 `--dce` | 4836 | 672 | 70940 | **76448**  (−43088, −36%) |

`data` and `bss` are byte-identical in all four builds — the pass removes code
and nothing else. **On bare that code IS SRAM**, so the six-target DCE port is
the largest SRAM lever measured so far on this profile, second only to the
64 KiB heap arena. On IDF, where `.text` can be flash-mapped, the same removal
is a flash win and buys no SRAM; that leg is NOT measured here.

### One unreferenced class, isolated

Two programs differing only by a class declaration nothing instantiates —
esp32c3, bare, **`--dce` on**, so this is what survives the existing pass:

| | code | data | bss | SRAM (bare) |
| --- | --- | --- | --- | --- |
| `begin end.` | 276 | 616 | 70936 | 71828 |
| + one class, 4 virtual methods | 544 | 1424 | 70936 | 72904 |
| delta | **+268** | **+808** | 0 | **+1076, all of it SRAM** |

**On bare both halves are SRAM and there is no flash/SRAM split to speak of.**
The earlier "SRAM cost is 3x the flash cost" line is withdrawn: it described an
IDF-shaped split on bare-profile numbers.

What survives the correction, and it is still the point of this ticket: this
ticket's headline figure — ~3.2 KB of the 15.6 KB surviving DCE — is the CODE
residue, the method bodies the VMT slots keep alive. The blob's own `.data`
bytes were noted here from the day it was opened (*"The blob's own bytes go too,
which is `.data`, not `.text`"*) and never quantified. Quantified, they are
**three times the code residue per class** (808 against 268) — so on either
profile the blob is the larger half of what this ticket would remove, and on IDF
it is the only half that is SRAM at all.

### How it scales

esp32c3, bare, `--dce`, **data** delta over the 616-byte baseline (the `.data`
half only; add ~67 B of code per virtual method on top):

    1 class x 1 method   + 448        2 classes x 1 method   + 768
    1 class x 4 methods  + 808        4 classes x 1 method   +1408
    1 class x 8 methods  +1288        4 classes x 4 methods  +2488

Roughly **~128 B one-off + ~200 B per class + ~120 B per virtual method**. The
4x4 row comes in 360 B UNDER that model and the reason is the fixture, not the
compiler: the generator names every class's methods `M1..Mn`, so the name
strings are shared between classes. **Do not read the per-method figure as
independent of naming** — a real program with distinct method names per class
pays more than this table suggests, not less.

### On the IDF profile the blob is `.data` too, and there is no `.rodata` at all

Same two programs, `--emit-obj --target=riscv32 --platform=esp`:

    .text   258788 -> 259056   (+268)
    .data     4072 ->   4800   (+728)     <- the blob
    .bss      9524 ->   9524   (unchanged)
    .rela.data 1320 ->  1740   (+420)     <- link-time, not runtime
    .rodata   absent in both

So the blob is emitted into a WRITABLE section on both profiles although nothing
writes it, and **there is no `.rodata` section for an IDF link to place**. That
is the seam with the read-only-data work and it only exists on IDF: frankh-3f's
measurement is that **read-only data buys ZERO SRAM on bare**, because moving
bytes between sections inside one RWX region changes nothing. Two answers to the
same bytes — move them out (IDF only), or stop emitting them (both profiles) —
and they compose: whatever is never emitted never reaches his classification, so
nothing is counted twice.

**Ownership settled with frankh-3f 2026-09-18: placement is his, reachability
and emission are mine.** His one request, recorded here so it is not lost: if
the layout of RTTI/VMT blobs inside `Data[]` changes, tell him, because his
classification keys on it. His open question, which is not this ticket's: whether
those tables are ever WRITTEN at runtime is unmeasured, and `.rela.data` growing
420 B alongside the blob means the slots carry relocations — whether those
pre-resolve at link time is his to settle.
