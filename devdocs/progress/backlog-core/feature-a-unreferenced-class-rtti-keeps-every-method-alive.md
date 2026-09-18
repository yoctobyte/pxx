---
prio: 30
track: A
summary: "MEASURED 2026-09-18 (frankB) UNDER THE ESP SRAM RE-RANK: the SRAM cost is 3x the flash cost and this ticket led with the flash number. One unreferenced class with four virtual methods costs **+808 B of data (SRAM) against +268 B of code (flash)** on esp32c3 bare WITH `--dce` already on; the ~3.2 KB headline below is the CODE residue, i.e. flash. `--dce` moves ZERO bytes of data or bss -- on test_esp_bare.pas it takes code 59664 -> 5320 (esp32c3) and 47924 -> 4836 (esp32s3) while data=672 and bss=70940 are byte-identical -- so the data-side pass described here is separate work, not a refinement of the existing one. Scales at roughly 128 B one-off + 200 B per class + 120 B per virtual method (the 4x4 row is 360 B under that because the fixture shares method NAMES between classes, so a real program pays more, not less). On the IDF profile the blob is `.data` too and there is NO `.rodata` section at all, which is the seam with the read-only-data group: a read-only blob is flash-mapped on ESP-IDF and costs zero SRAM, so move-them-out and stop-emitting-them are two answers to the same bytes and they compose. Ownership being settled with frankh-3f before either side writes code."
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

## Measured 2026-09-18 (frankB) — the SRAM cost is 3x the flash cost, and this ticket leads with the flash number

Measured after the owner re-ranked ESP to *"minimizing SRAM usage is prio"*.
**Profile named beside every number, because bare and IDF are different shapes
and under this re-rank that is load-bearing rather than a caveat.**

### `--dce` moves ZERO bytes of data or bss. Not approximately zero.

`test/test_esp_bare.pas`, `--esp-profile=bare`:

| target | code | data | bss |
| --- | --- | --- | --- |
| esp32c3 plain | 59664 | 672 | 70940 |
| esp32c3 `--dce` | **5320** | **672** | **70940** |
| esp32s3 plain | 47924 | 672 | 70940 |
| esp32s3 `--dce` | **4836** | **672** | **70940** |

Code drops by 91% and 90%. Data and bss are byte-identical. **The pass that was
ported to six targets this week is worth ~90% of FLASH on an ESP program and
exactly nothing in SRAM**, which is what makes the data-side pass this ticket
describes a separate piece of work rather than a refinement of the existing one.

### One unreferenced class, isolated

Two programs differing only by a class declaration nothing instantiates —
esp32c3, bare, **`--dce` on**, so this is what survives the existing pass:

| | code | data | bss |
| --- | --- | --- | --- |
| `begin end.` | 276 | 616 | 70936 |
| + one class, 4 virtual methods | 544 | **1424** | 70936 |
| delta | **+268 (flash)** | **+808 (SRAM)** | 0 |

**808 bytes of SRAM against 268 bytes of flash — the SRAM cost is 3.0x the flash
cost, and it is the one nothing can remove.** This ticket's headline figure,
~3.2 KB of the 15.6 KB surviving DCE, is a CODE number: it is the method bodies
the VMT slots keep alive, i.e. flash. That is still true and it is no longer the
expensive half. The blob's own bytes were noted here as `.data` from the start
("The blob's own bytes go too, which is `.data`, not `.text`") and never
quantified; quantified, they are the larger number.

### How it scales

esp32c3, bare, `--dce`, data delta over the 616-byte baseline:

    1 class x 1 method   + 448        2 classes x 1 method   + 768
    1 class x 4 methods  + 808        4 classes x 1 method   +1408
    1 class x 8 methods  +1288        4 classes x 4 methods  +2488

Roughly **~128 B one-off + ~200 B per class + ~120 B per virtual method**. The
4x4 row comes in 360 B UNDER that model and the reason is the fixture, not the
compiler: the generator names every class's methods `M1..Mn`, so the name
strings are shared between classes. **Do not read the per-method figure as
independent of naming** — a real program with distinct method names per class
pays more than this table suggests, not less.

### On the IDF profile it is `.data` too, and there is no `.rodata` at all

Same two programs, `--emit-obj --target=riscv32 --platform=esp`:

    .text   258788 -> 259056   (+268)
    .data     4072 ->   4800   (+728)     <- the blob
    .bss      9524 ->   9524   (unchanged)
    .rela.data 1320 ->  1740   (+420)     <- link-time, not runtime
    .rodata   absent in both

So the blob is emitted into a WRITABLE section on both profiles although nothing
writes it. That matters because it is the seam with the read-only-data work:
**a `.rodata` RTTI blob is flash-mapped on ESP-IDF and costs zero SRAM.** Two
different answers to the same bytes — move them out, or stop emitting them —
and they compose: bytes moved to flash that are then never emitted are a win
counted once. Ownership is being settled with frankh-3f before either side
writes code; this section is evidence only.

Whether the blob CAN be read-only is not settled here: `.rela.data` grows by 420
bytes alongside it, so the slots carry relocations, and whether those can be
pre-resolved at link time (bare links at a fixed SRAM map; IDF does not) is the
read-only-data group's question, not this one.
