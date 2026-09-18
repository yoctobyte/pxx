---
prio: 30
track: A
summary: "THIS TICKET'S PASS CANNOT DO WHAT IT SAYS, MEASURED 2026-09-18 (frankB) -- **the blocker is the REGISTRY and every ordinary class is in it.** ClassIsStreamable is `ClassHasPublished or ClassImplementsGuidedInterface`, and a class declared with NO visibility keyword defaults to PUBLISHED -- so `TU = class ... end` reports streamable=1 and `TU = class public ... end` reports 0, identical blob/vmt either side, the registry entry being the 24-byte difference in data=. Registry membership is name-reachability at run time, which this ticket's own Watch out lists as what makes a blob undroppable, so the pass AS SPECIFIED would drop almost nothing on ordinary Pascal. **And the ticket's own headline example is one of them**: TInterfacedObject, which holds every method in the residue table, is streamable=1 because it implements a guided interface. THE LEVER IS THAT THE REGISTRY IS AN UNCONDITIONAL ROOT: it is emitted whenever any class is streamable and its only consumer is IR_RTTI_REG from one AST node (AN_RTTI_REG, verified across all six backends), so in a program that never asks for it the registry is dead data rooting every streamable class. Make it conditional and streamable stops being a root, at which point the residue becomes droppable. MEASURED: AN_RTTI_REG comes only from the `__rttireg()` intrinsic, which inside lib/ is called from three files (rtl/typinfo.pas GetClass, pcl/controls.pas, pcl/gtk3widgets.pas); a program with no `uses` contains ZERO GetClass/FindClass/typinfo symbols in its object, so typinfo is not pulled ambiently and its registry is emitted and never read -- silently, because emit.inc DROPS an unresolved registry reference rather than failing. The pass must key on the NODE and never on `uses typinfo`, since __rttireg() is a public intrinsic a user program can call directly. THE --emit-obj EDGE IS MOOT, measured not argued: two objects in one binary, B finds its OWN class and NOT A's (a=1 B_finds_A=0 B_finds_its_own=1), because each object carries its own Data[] and its own registry -- so the cross-object lookup cannot be broken by node-conditional emission and no --emit-obj arm is needed. SEPARATE DEFECT UNCOVERED: emit.inc DROPS an unresolved registry reference and the intrinsic reads nil, so a registry with no reader gives no diagnostic and a reader with no registry gives no refusal -- the silent-negative shape, and why this went unnoticed. Weights via the new PXXDBG=a.rttiweight, profile named: hello hosted x86-64 = 5 classes, RTTI data 664, direct VMT-slot code 409; hello esp32c3 BARE --dce = 1 class, data 160 (the interface machinery is not pulled in on bare at all); esp_pal_fdsem_baseline.pas as an IDF xtensa object = 7 classes, data 608, direct code 556. directmethbytes is neither bound cleanly -- it over-counts inherited slots and under-counts far more, since the ~3.2 KB here is dominated by PXXTIOGetInterface/PXXIntfIMTOf/PXXVarStrAppend/PXXVarClear, runtime routines the methods REACH rather than methods in any VMT; only dce.inc's walk can price the closure. || AND THE SRAM ACCOUNTING, corrected the same day: MEASURED 2026-09-18 (frankB), AND CORRECTED THE SAME DAY -- ON THE BARE PROFILE CODE IS SRAM. defs.inc's own map: qemu's esp32c3 models internal SRAM as ONE RWX region and the whole image (code+data+bss) loads at the IRAM org, so SRAM(bare) = code + data + bss. A first pass of the measurement below read data/bss as the SRAM and code as the flash -- that is the IDF shape and it is false on bare; caught by frankh-3f. Consequences: (a) `--dce` saves **54344 B of SRAM on bare** (esp32c3 131276 -> 76932, -41%; esp32s3 -36%), not zero -- it is the largest SRAM lever measured on this profile after the 64 KiB heap arena; on IDF, where .text can be flash-mapped, the same removal is a flash win and that leg is unmeasured. (b) One unreferenced class with four virtual methods costs +268 B code and +808 B data = **+1076 B, all of it SRAM on bare**; the earlier `SRAM is 3x the flash cost` line is WITHDRAWN as an IDF-shaped split applied to bare numbers. What survives: this ticket's ~3.2 KB headline is the CODE residue (method bodies held by VMT slots), while the blob's own .data bytes -- noted here from the day it opened and never quantified -- are 3x that per class, so the blob is the larger half on either profile and the only half that is SRAM at all on IDF. (c) The fleet's stated bare baseline `data=616 bss=70936, SRAM=71552` omits code and is really ~129452 at plain -O. Scales at ~128 B one-off + ~200 B per class + ~120 B per virtual method, and the 4x4 row lands 360 B UNDER that because the fixture shares method NAMES between classes -- a real program pays more, not less. On IDF the blob is .data too with .rela.data +420 and NO .rodata section at all. Ownership settled with frankh-3f: placement is his, reachability and emission are mine, and read-only placement buys ZERO SRAM on bare because moving bytes inside one RWX region changes nothing."
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

## Measured 2026-09-18 (frankB) — THE BLOCKER IS THE REGISTRY, AND EVERY ORDINARY CLASS IS IN IT

The instrument this section is built on is `PXXDBG=a.rttiweight`
(`ReportRTTIWeight`, rtti_emit.inc), which prices each class's RTTI in the two
currencies it is paid in, and flags `streamable` — membership of the RTTI
registry, i.e. reachable BY NAME at run time, which the **Watch out** section
above already names as the thing that makes a blob undroppable.

### The finding: `TFoo = class ... end` is registry-rooted

`ClassIsStreamable` is `ClassHasPublished or ClassImplementsGuidedInterface`, and
a class declared with **no visibility keyword defaults to `published`**. So an
ordinary class declaration is in the registry. One keyword apart, nothing else
changed:

    type TU = class            procedure A; virtual; ...   streamable=1
    type TU = class public     procedure A; virtual; ...   streamable=0

identical `blob=112 vmt=64 vmtslotprocs=5 directmethbytes=220` on both sides, and
the registry entry is the 24-byte difference in `data=` (1448 against 1424 on
esp32c3 bare).

**So the pass as this ticket specifies it would drop almost nothing on ordinary
Pascal**, because almost every class is name-reachable by default. That is not an
argument against the ticket; it relocates it.

### And the ticket's own headline example is one of them

`TInterfacedObject` — which holds every method in the residue table at the top of
this ticket — reports **`streamable=1`**, because it implements a guided
interface. The class the ticket exists to prune is excluded by the ticket's own
Watch out.

### Where the lever actually is: the registry is an UNCONDITIONAL root

The registry is emitted whenever any class is streamable, and its only consumer
is `IR_RTTI_REG`, from a single AST node (`AN_RTTI_REG`) — verified by grep
across all six backends; `emit.inc` resolves the `-100` sentinel to
`RTTIRegistryOff` and drops the reference when there is no table. **In a program
that never asks for the registry, the registry is dead data rooting every
streamable class in the image.**

Make the registry conditional on the program containing an `IR_RTTI_REG` and
`streamable` stops being a root for such programs — at which point
`TInterfacedObject` and the ticket's residue become droppable and the data-side
walk this ticket describes has something to walk.

**Measured, not assumed.** `AN_RTTI_REG` comes from exactly one place, the
`__rttireg()` intrinsic (`pasparser_expr.inc`, and its NilPy twin). Inside
`lib/`, `__rttireg()` is called from three files only — `lib/rtl/typinfo.pas`
(`GetClass`), `lib/pcl/controls.pas`, `lib/pcl/gtk3widgets.pas`. A program that
uses none of them never emits the node: built `--emit-obj`, a program with no
`uses` at all contains **zero** `GetClass`/`FindClass`/typinfo symbols, so
typinfo is not pulled ambiently. Its registry is therefore emitted and never
read — and `emit.inc`'s drop path means an unreferenced registry is silent
rather than loud, which is why nobody noticed.

The caveat the pass must respect: `__rttireg()` is a public intrinsic, so a USER
program can call it directly without going through `lib/`. The condition has to
be "does this program contain an `IR_RTTI_REG` node", never "does it use
typinfo" — the second is the shape of a hand-maintained union, which is the
failure `bug-a-a-frontend-cannot-see-that-a-backend-calls-library-routines-it-never-mentions`
records from the other side.

### What it weighs today, profile named beside every number

| subject | classes | streamable | RTTI data | direct VMT-slot code | of which NOT streamable |
| --- | --- | --- | --- | --- | --- |
| hello, hosted x86-64 | 5 | 1 | 664 | 409 | data 496, code 44 |
| hello, esp32c3 **bare** `--dce` | 1 | 0 | 160 | 1 | data 160, code 1 |
| `esp_pal_fdsem_baseline.pas`, **IDF** object xtensa | 7 | 1 | 608 | 556 | data 472, code 0 |

**`directmethbytes` is neither bound cleanly and the instrument says so.** It
OVER-counts where a subclass inherits a slot (a body reached from two VMTs is
counted twice) and UNDER-counts far more, because it is the DIRECT edge only:
this ticket's ~3.2 KB is dominated by `PXXTIOGetInterface`, `PXXIntfIMTOf`,
`PXXVarStrAppend` and `PXXVarClear`, which are runtime routines the methods
REACH, not methods in any VMT. Only the code-side walk in `dce.inc` can price
the closure.

**Profiles do not add the same way.** Under `--esp-profile=bare` the whole image
loads into one RWX IRAM region, so both columns are SRAM. Under `--platform=esp`
the code can be flash-mapped and only the data column is SRAM. Hosted, neither
is. Note the bare hello carries **one** class — the interface machinery is not
pulled in there at all — so the prize on bare is ~160 bytes and the population
this ticket is really about is the IDF/hosted one.

### Layout note from the read-only-data group

**AND A SELF-RELATIVE WORD IS THE TRAP, WHICH IS THIS WEEK'S DCE DEFECT ARRIVING
ON THE DATA SIDE.** frankh-3f, correcting his own earlier note, `120e3a3cd`: the
RTTI layout descriptors carry SELF-RELATIVE 32-bit words — `typeRef` /
`baseTypeRef` are `UClsRTTIOff[ci] - (pos + 12|16)`, decoded by builtinheap as
`pos + word`, at five sites in `rtti_emit.inc`. His read-only split broke them
**with no fault**: `rdyn 0` instead of 3 and a 999-object leak, a plausible wrong
value far from the cause. Each such word is now recorded with
`AddDataRelFix(pos, target)` (util.inc) and recomputed through `DataRemap` at
write time; identity when nothing is split.

**Rule for this ticket's half: any new data word holding `target - pos` must call
`AddDataRelFix(pos, target)` beside its `PatchDataI32`.** Absolute pointers via
`AddDataPtrFix` were always fine.

This is exactly the shape that cost a day on the code side this week: DCE
re-aimed every `CodeRef` with a raw x86-64 rel32 over encoded branch WORDS,
because a displacement's SITE moves even when its TARGET is final. A blob-
dropping or `Data[]`-compacting pass has the same hazard with `AddDataRelFix`
as the register of sites to re-apply — and, as on the code side, the table that
gets forgotten is the parallel one nobody enumerated.

frankh-3f, `b05b7bb0a`: x86-64 executables now PERMUTE `Data[]` at write time —
ranges marked with `RoRangeAdd` move to an R segment and every data address
resolves through `DataRemap` in elfwriter.inc. Offsets inside `Data[]` are
unchanged at emission, so nothing emitted here needs to know. If RTTI/VMT blobs
should ever be read-only it is one `RoRangeAdd(start, end)` per blob at emission
**after a never-written measurement**, and the R segment is itself that
measurement, because a store faults. Ownership split agreed the same day:
**whether a blob is emitted is this ticket's; where a survivor lives is his.**

### The `--emit-obj` edge, closed rather than inherited

Node-conditional emission is obviously safe for an executable: no `IR_RTTI_REG`,
nothing reads the registry, drop it. Under `--emit-obj` it is not obviously safe
— object A declares the classes, object B holds the `__rttireg()` node, and if
A's registry went because A has no node, B's lookup would find nothing. That is
`decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit`
wearing a different hat.

**It is moot, and measured rather than argued.** Two objects, linked into one
binary with a gcc `main`:

    objA   declares TOnlyInA (no visibility keyword -> published -> streamable),
           constructs it and calls a virtual method.  streamable=2
    objB   `uses typinfo`, declares TOnlyInB, and asks GetClass for BOTH names.

    a=1   B_finds_A=0   B_finds_its_own=1

**B finds its own class and cannot see A's, today, with both registries present
and both objects in the same executable.** Each object carries its own `Data[]`
and its own registry, and `__rttireg()` in B resolves to B's. The cross-object
lookup this edge worries about does not work now, so node-conditional emission
cannot break it and needs no `--emit-obj` arm.

`B_finds_its_own=1` is the control that makes the 0 mean something: without it a
zero would equally describe a `GetClass` that never works, and the row would be
a guard that cannot fail. Scope: x86-64 hosted objects, one pair, gcc link. It
is consistent with the export-side measurement on the decide page — both objects
have zero undefined symbols of any kind, because each carries everything it
reaches.

### A separate defect this uncovered: an unresolved registry reference is DROPPED, silently

`emit.inc`'s `-100` sentinel path, when `RTTIRegistryOff < 0`, sets
`DATAREF_DROP` and the intrinsic then reads nil — commented there as *"a
documented answer, not a defect: a module that publishes no classes has no
registry"*. That reading is fine for the case it was written for and it is also
why an emitted-and-never-read registry went unnoticed for as long as it has:
**nothing on either side of this is loud.** A registry with no reader produces no
diagnostic, and a reader with no registry produces a nil rather than a refusal.
It is the silent-negative shape — an absence that reads as working.

Not fixed here, and it is not this ticket's subject; recorded because whoever
implements node-conditional emission will be changing exactly this predicate and
should decide deliberately whether the nil stays silent.
