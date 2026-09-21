---
prio: 75
track: S
type: bug
status: backlog
found: 2026-09-21
found-by: frankB
owner: ""
blocked-by: []
summary: "NOT LATENT AFTER ALL -- MEASURED 2026-09-21, THIS COLLISION IS 92% OF AN EMPTY BARE ESP IMAGE. builtinheap.pas defines PXXDynSetLen with the same signature three times (:533, :2271, :5238); on the ESP-class ISAs two are visible at once and the compiler warns that the later body wins. THE MECHANISM IS THE ORPHAN, NOT THE BINDING: the LOSING body is still emitted into the image but is not registered as a proc body, so DceOwnerOf answers <0 for every call site inside it and the pass classifies them as `called from unowned code` -- which means (a) those bytes can never be dropped, DCE only drops registered bodies, and (b) every callee they name is ROOTED unconditionally. One orphan pins the entire allocator core. Proven by renaming ONE definition in an isolated compiler+builtin sandbox (repo untouched): empty program bare xtensa 11348 B -> 864 B, live bodies 12 (8872 B) -> 2 (150 B), and PXXAlloc/PXXBlockCopy/PXXFree/PXXMemZero/HeapMmap/PXXHeapExhausted/PXXDynArrayReleaseEsp/PXXHdrRC/PXXHdrBase/PXXHdrInit all correctly dropped. Real fixtures: test_esp_bare xtensa 13788->4968 and riscv32 16988->5380; test_esp_exception xtensa 28928->20108 and riscv32 37028->25420; a SetLength program xtensa 34724->32576, riscv32 44020->41172. Behaviour identical -- both arms boot under Espressif qemu on esp32s3 AND esp32c3 and print the same answer. THIS ALSO RECONCILES THE IMAGE-SIZE PAIR IN THE LOGBOOK: the Makefile records 4836 B for test_esp_bare on 2026-09-19 and the de-duplicated build measures 4968 B today, so the ~2.85x growth was this, not RTL drift. NOT FIXED HERE ON PURPOSE: the rename is a DIAGNOSTIC. Which of the three bodies ESP should bind is a semantic question about builtinheap -- note that today ESP binds the NON-ESP body and the ESP-specific path through PXXDynArrayReleaseEsp is dead code, which may itself be wrong. THE CLASS IS BIGGER THAN THIS ROUTINE: any duplicate same-signature builtin definition creates an undroppable orphan that roots its callees, so the general remedy is to make the compiler REFUSE the duplicate rather than warn."
---

# Three different `PXXDynSetLen` bodies are visible at once on every ESP ISA

## Measured

At HEAD (`compiler/pascal26 = 1a31826169bc`) and identically under pin v413
(`f94c2a7e2396`), compiling `test/test_esp_bare.pas`:

| target | `duplicate definition of 'PXXDynSetLen'` |
| --- | --- |
| `--target=xtensa --esp-profile=bare` | 1 |
| `--target=riscv32 --esp-profile=bare` | 1 |
| `--target=xtensa` | 1 |
| `--target=riscv32` | 1 |
| `--target=arm32` | 0 |
| `--target=i386` | 0 |
| hosted x86-64 (no `--target`) | 0 |

**CORRECTED 2026-09-21, and the first table measured the FIXTURE as well as the
compiler.** The table above was taken with `test_esp_bare.pas`, which opens with
`{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}` — so the *program* supplies the
define, and the rows that fire without `--esp-profile=bare` fire because of the
fixture, not the target. Re-measured with an empty program and with a program
whose only content is those two `{$define}` lines:

| program | flags | duplicates |
| --- | --- | --- |
| empty | `--target=xtensa` | **0** |
| empty | `--target=xtensa --esp-profile=bare` | 1 |
| defines `PXX_ESP` | `--target=xtensa` | **1** |
| defines `PXX_ESP` | `--target=xtensa --esp-profile=bare` | 1 |

**The trigger is `PXX_ESP` being defined — by the profile or by the source —
not the ISA.** An ESP-class ISA is merely where that normally happens. Stated
because the difference decides who can hit it: any program that defines
`PXX_ESP` itself pays this, on any target where those arms compile.

**Census, same day:** compiling an empty program across xtensa, riscv32 (each
with and without `--esp-profile=bare`), arm32, aarch64, i386, wasm32 and hosted
x86-64 yields exactly **one** duplicated name tree-wide — `PXXDynSetLen`. So the
class has one live instance today; the mechanism below is what makes it worth a
guard anyway. The compiler's own text names the
hazard:

> duplicate definition of 'PXXDynSetLen' with the same parameter types; the
> later body wins, but calls written between the two bind to the earlier one

## Why this is not a harmless duplicate

The three bodies are pairwise **different**, not copies:

| definition | size |
| --- | --- |
| `builtinheap.pas:533` | 235 lines |
| `builtinheap.pas:2271` | 34 lines |
| `builtinheap.pas:5238` | 59 lines |

So "the later body wins" is not a tie-break between identical texts — it selects
between three different implementations of dynamic-array `SetLength`, and a call
site's **lexical position inside the builtin** decides which it gets.

## What is NOT established

- **Which two of the three are simultaneously active**, and under exactly which
  define combination. See the warning below.
- **Whether any call site currently sits between two definitions.** If none
  does, today's images are correct by luck of layout, which is precisely what
  makes this latent rather than academic.
- No wrong behaviour is observed: the bare qemu boot rows still diff UART clean
  against the x86-64 oracle on both chips.

## Do not read the conditionals — ask the compiler

`builtinheap.pas` lines 13-14 are **comment prose** quoting
`{$ifdef CPU_XTENSA}{$define PXX_ESP}` in order to describe a past bug. A
directive scanner that does not skip comments treats those as real and reports a
nesting stack that never unwinds, yielding impossible conditions such as
`ifdef PXX_ESP AND ifndef PXX_ESP` at one line. Three separate static attempts
produced three contradictory answers here before the approach was abandoned.

The reliable instruments are the ones used above: vary one flag at a time and
count the warning, and ask `git log -S` when each copy appeared.

## What would retire this

Either one definition per ISA with the others removed or renamed, or — if all
three are genuinely wanted — a build-time refusal when two same-signature
bodies are visible at once, so the binding can never be decided by layout.


## 2026-09-21 — MEASURED: THIS IS 92% OF AN EMPTY BARE ESP IMAGE

Filed earlier the same day as a latent hazard on the strength of the compiler's
warning. It is not latent. It is the dominant cost of every bare ESP image.

### The mechanism is the ORPHAN, not the binding

The warning describes a *binding* ambiguity. The expensive half is what happens
to the body that loses:

1. it is still **emitted** into the image;
2. it is **not registered** as a proc body, so `DceOwnerOf` answers `< 0` for
   every call site inside it;
3. the pass therefore labels those calls **`called from unowned code`** — and
   that is a root.

DCE only drops *registered* bodies, so the orphan's bytes are undroppable, and
every routine it calls is pinned. `PXXDynSetLen`'s orphan calls
`PXXDynArrayReleaseEsp` (`builtinheap.pas:2282`, `:2303`), which is how the whole
allocator core ends up live in a program that does nothing.

The tell is visible in `--dce-why` without any experiment: the **registered**
body is reported `PXXDynSetLen <- DROPPED` while `PXXDynArrayReleaseEsp` is
simultaneously live `<- [called from unowned code]`. A dropped caller and a live
callee is only possible if the real caller is not a body.

### Measured, by renaming ONE definition in an isolated sandbox

The repo was never modified: a copy of `compiler/pascal26` plus
`compiler/builtin/**` in a scratch directory, `--where` confirming it resolved
the sandbox builtin, and the pristine baseline reproducing `11348 B` exactly
before any edit.

| program | target | as-is | de-duplicated |
| --- | --- | --- | --- |
| empty program | xtensa | 11348 B | **864 B** |
| `test_esp_bare` | xtensa | 13788 B | 4968 B |
| `test_esp_bare` | riscv32 | 16988 B | 5380 B |
| `test_esp_exception` | xtensa | 28928 B | 20108 B |
| `test_esp_exception` | riscv32 | 37028 B | 25420 B |
| `SetLength` program | xtensa | 34724 B | 32576 B |
| `SetLength` program | riscv32 | 44020 B | 41172 B |

Empty program live bodies go from **12 (8872 B) to 2 (150 B)**.

**Behaviour is unchanged**: the `SetLength` program boots under Espressif qemu on
**both** esp32s3 and esp32c3 in **both** arms and prints the same answer, so the
orphan was contributing nothing but bytes.

### THE SRAM DELTA IS ZERO, AND SRAM IS THE RESOURCE THAT COUNTS

**Every number above is an IMAGE size, and the owner ruled on 2026-09-20 that
image size is the lesser issue:** *"SRAM here is most relevant, ESP's have
'plenty' flash memory so that's a lesser issue."* So the headline needed the
column I had not taken. Taken 2026-09-21, `data + bss`, same eight rows:

| program | target | SRAM as-is | SRAM de-duplicated | delta |
| --- | --- | --- | --- | --- |
| empty | xtensa / riscv32 | 67464 B | 67464 B | **0** |
| `test_esp_bare` | xtensa / riscv32 | 67524 B | 67524 B | **0** |
| `test_esp_exception` | xtensa / riscv32 | 67496 B | 67496 B | **0** |
| `SetLength` program | xtensa / riscv32 | 67500 B | 67500 B | **0** |

**Exactly zero, not merely small.** Dropping the orphan removes CODE, and the
routines it rooted carry no static data, so nothing leaves SRAM.

**So this must not travel as an ESP memory win.** It is worth doing — 13x on the
image, flash-constrained parts, flashing time — and it does not, on its own,
outrank whatever else competes for the first hardware day.

(Deterministic, for the record: `code`/`data`/`bss` are outputs of the compiler
and its sources, so these rows do not depend on box load, and the sandbox holds
its own copy of `pascal26` and `compiler/builtin/**`, so a rebuild elsewhere
cannot move them either.)

### WHERE THE ESP SRAM ACTUALLY IS, found by taking that column

An **empty** bare program reserves **67,464 B**, and `HEAP_ARENA` is 65,536 of
it — **97.1%** of an empty program's SRAM, and ~23% of the 276,832 B free DRAM
pool, reserved unconditionally under `{$ifdef PXX_ESP}` (`builtinheap.pas:1155`,
`EspArena : array[0..(HEAP_ARENA div 8) - 1] of Int64`).

**That is the same shape as `bug-a-the-signal-alt-stack-is-32768-bytes-of-
unconditional-bss`**, fixed on 2026-09-18 by reserving the alt stack *iff* a
handler can exist. Second unconditional BSS reservation to dominate ESP SRAM in
four days.

**And the de-duplication above is what makes the condition decidable**: once the
orphan is gone, DCE *proves* `PXXAlloc` dead in a non-allocating program — it is
dropped, measured — so the arena provably has no reader. Reserved-iff-reachable
is then the same one-line predicate `16ebf18ce` used. Belongs under
`umbrella-an-esp32-image-is-as-small-as-it-can-be`; not filed separately here
because it wants a measurement against the pin now landing.

### It reconciles the logbook's two size rows

`Makefile:test-esp-bare` records `47872 -> 4836` for this fixture on 2026-09-19.
The de-duplicated build today measures **4968 B**. So the ~2.85x growth logged as
*unreconciled* was this collision, not RTL drift — and the two rows can now be
collapsed, with this as the reason.

### Why it is not fixed in this commit

The rename is a **diagnostic**, not a fix. Which of the three bodies ESP ought to
bind is a semantic question about `builtinheap`, and the answer is not obvious:
today ESP binds the **non-ESP** body, and the ESP-specific path through
`PXXDynArrayReleaseEsp` is dead. That may itself be the wrong outcome, in which
case the fix changes behaviour rather than only size.

### The class, which is worth more than this routine

Any duplicate same-signature definition in a builtin produces an undroppable
orphan that roots its callees. The general remedy is to make the compiler
**refuse** it instead of warning — a warning nobody reads has been costing 10 KB
per ESP image since June.
