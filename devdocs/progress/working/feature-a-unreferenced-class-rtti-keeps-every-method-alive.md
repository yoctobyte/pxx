---
prio: 30
track: A
summary: "LARGEST REMAINING RUNG OF THE ESP UMBRELLA AS OF 2026-09-20 (frankS) -- AND THE PASS SPECIFIED BELOW DOES NOT REACH IT. Measured with --dce-why on the nilpy-c3 demo once the eval() interpreter stopped being linked: 172,637 B / 149 bodies are rooted `vmt/rtti slot`, 21% of the live image, and the classes holding those slots are all LEGITIMATELY LIVE (TPyList, TPyDict, TPyFile), so an unreferenced-CLASS criterion reaches none of it. The cost is a per-METHOD slot nothing can dispatch to: `TPyFile.writelines` alone heads three of the nine largest rows, 115,606 B, because it accepts any sequence and drags the iterator-drain path into a program that never opens a file. That is consistent with the `NEVER FIRES FOR NILPY` finding below rather than contradicting it -- the registry work cleared a different root. Whoever takes this should start from the 2026-09-20 section, which names the chains and says what the instrument cannot yet answer (a per-root SUBTREE total). || THE BLOCKER IS REMOVED AND THE PASS IS NOW WRITABLE AND UNWRITTEN, 2026-09-19 (frankB, `5bde993c5`). **The registry is no longer an unconditional root**: it is emitted only when the program contains a reader -- a parsed `__rttireg()` node -- so a program that never reflects no longer roots every class by name. That was the one thing standing between this ticket and its own proposal, and it cost 24 B directly on a hello (8-byte count slot + one 16-byte entry), which is NOT the win and must not travel as one: no blob is dropped, because Pass 1 still reserves a header per class for ClassName and the is/as backlink chain. **What remains is the pass itself -- nobody has written it**, and the next seat should read the `PARKED`/`BUILT` sections in the body before starting. IT NEVER FIRES FOR NILPY, by construction and not by degree: every NilPy program pulls pylib, `pylib.pas:40` is `uses ... typinfo`, and `typinfo.pas:755` is `reg := __rttireg()`, so `print(1)` alone reports reader=1. That weakens the ESP/SRAM case on NilPy specifically -- measure both frontends or name the one you measured. A follow-on that would fix it (move GetClass to its own unit) is fully analysed, priced at ~24-40 B against a four-file `uses` rewrite in Track B's ground, and DECLINED as a second enabler for a pass that does not exist; its prerequisite check is recorded UNRUN and labelled. || WHY IT WAS THE BLOCKER, MEASURED 2026-09-18 and still the reason the pass is shaped this way: ClassIsStreamable is `ClassHasPublished or ClassImplementsGuidedInterface`, and a class declared with NO visibility keyword defaults to PUBLISHED -- so `TU = class ... end` reports streamable=1 and `TU = class public ... end` reports 0, identical blob/vmt either side, the registry entry being the 24-byte difference in data=. Registry membership is name-reachability at run time, which this ticket's own Watch out lists as what makes a blob undroppable, so the pass AS SPECIFIED would have dropped almost nothing on ordinary Pascal while that held. **And the ticket's own headline example is one of them**: TInterfacedObject, which holds every method in the residue table, is streamable=1 because it implements a guided interface. THE LEVER WAS THAT THE REGISTRY WAS AN UNCONDITIONAL ROOT: it is emitted whenever any class is streamable and its only consumer is IR_RTTI_REG from one AST node (AN_RTTI_REG, verified across all six backends), so in a program that never asks for it the registry is dead data rooting every streamable class. Making it conditional (done, 5bde993c5) stops streamable being a root, at which point the residue becomes droppable -- that is the state the tree is in now. MEASURED: AN_RTTI_REG comes only from the `__rttireg()` intrinsic, which inside lib/ is called from three files (rtl/typinfo.pas GetClass, pcl/controls.pas, pcl/gtk3widgets.pas); a program with no `uses` contains ZERO GetClass/FindClass/typinfo symbols in its object, so typinfo is not pulled ambiently and its registry is emitted and never read -- silently, because emit.inc DROPS an unresolved registry reference rather than failing. It keys on the NODE and never on `uses typinfo`, since __rttireg() is a public intrinsic a user program can call directly; the flag is set at PARSE time because EmitRTTI runs before any IR lowering, which makes it conservative -- a __rttireg() in never-lowered code still emits the registry. THE --emit-obj EDGE IS MOOT, measured not argued: two objects in one binary, B finds its OWN class and NOT A's (a=1 B_finds_A=0 B_finds_its_own=1), because each object carries its own Data[] and its own registry -- so the cross-object lookup cannot be broken by node-conditional emission and no --emit-obj arm is needed. SEPARATE DEFECT UNCOVERED: emit.inc DROPS an unresolved registry reference and the intrinsic reads nil, so a registry with no reader gives no diagnostic and a reader with no registry gives no refusal -- the silent-negative shape, and why this went unnoticed. Weights via the new PXXDBG=a.rttiweight, profile named: hello hosted x86-64 = 5 classes, RTTI data 664, direct VMT-slot code 409; hello esp32c3 BARE --dce = 1 class, data 160 (the interface machinery is not pulled in on bare at all); esp_pal_fdsem_baseline.pas as an IDF xtensa object = 7 classes, data 608, direct code 556. directmethbytes is neither bound cleanly -- it over-counts inherited slots and under-counts far more, since the ~3.2 KB here is dominated by PXXTIOGetInterface/PXXIntfIMTOf/PXXVarStrAppend/PXXVarClear, runtime routines the methods REACH rather than methods in any VMT; only dce.inc's walk can price the closure. || AND THE SRAM ACCOUNTING, corrected the same day: MEASURED 2026-09-18 (frankB), AND CORRECTED THE SAME DAY -- ON THE BARE PROFILE CODE IS SRAM. defs.inc's own map: qemu's esp32c3 models internal SRAM as ONE RWX region and the whole image (code+data+bss) loads at the IRAM org, so SRAM(bare) = code + data + bss. A first pass of the measurement below read data/bss as the SRAM and code as the flash -- that is the IDF shape and it is false on bare; caught by frankh-3f. Consequences: (a) `--dce` saves **54344 B of SRAM on bare** (esp32c3 131276 -> 76932, -41%; esp32s3 -36%), not zero -- it is the largest SRAM lever measured on this profile after the 64 KiB heap arena; on IDF, where .text can be flash-mapped, the same removal is a flash win and that leg is unmeasured. (b) One unreferenced class with four virtual methods costs +268 B code and +808 B data = **+1076 B, all of it SRAM on bare**; the earlier `SRAM is 3x the flash cost` line is WITHDRAWN as an IDF-shaped split applied to bare numbers. What survives: this ticket's ~3.2 KB headline is the CODE residue (method bodies held by VMT slots), while the blob's own .data bytes -- noted here from the day it opened and never quantified -- are 3x that per class, so the blob is the larger half on either profile and the only half that is SRAM at all on IDF. (c) The fleet's stated bare baseline `data=616 bss=70936, SRAM=71552` omits code and is really ~129452 at plain -O. Scales at ~128 B one-off + ~200 B per class + ~120 B per virtual method, and the 4x4 row lands 360 B UNDER that because the fixture shares method NAMES between classes -- a real program pays more, not less. On IDF the blob is .data too with .rela.data +420 and NO .rodata section at all. Ownership settled with frankh-3f: placement is his, reachability and emission are mine, and read-only placement buys ZERO SRAM on bare because moving bytes inside one RWX region changes nothing."
status: working
owner: frankb-8e
---

# An unreferenced class keeps every one of its methods alive

- **Type:** feature (codegen / emission size) — Track A, tag O
- **Status:** backlog — opened 2026-08-21; the registry-root blocker cleared 2026-09-19 (`5bde993c5`), the pass itself still unwritten
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
the registry entry is the **24-byte** difference in `data=` on **esp32c3 bare**
and the **16-byte** difference on **hosted x86-64** — re-derived 2026-09-18 after
`c44fa2642`, where bare reads 1000 against 976 and hosted 4808 against 4792.

**The label changes a term, so name it rather than carrying one number into the
other profile.** The absolute `data=` on bare has moved since this section was
first written (1448 -> 1000, from the heap-arena knob and the commits around it);
**the DELTA has not**, which is what makes the delta the quantity to quote and
the absolute the one to re-measure.

**The 8-byte gap between profiles is NOT pointer width — I wrote that, and it is
wrong in the direction that should have caught it, since bare here is riscv32 and
has the NARROWER pointers.** Re-derived from the emitter instead of reasoned: a
registry entry is a fixed **16 bytes** (`DataPutZeros(16)`, two pointer-fixed
slots, target-independent), and the table also carries an 8-byte COUNT slot that
exists only when at least one class is streamable. Hosted goes streamable 2 -> 1,
so one entry leaves and the count slot stays: **16**. Bare goes 1 -> 0, so the
whole table goes: 8 + 16 = **24**. Same entry size on both profiles; the
difference is whether the class being removed is the LAST streamable one.

### THE REGISTRY'S RUN-TIME WRITABILITY IS UNMEASURED, NOT SETTLED (2026-09-19)

Recorded because an exclusion with a reason attached reads as settled, and this
one is not — the hazard-block decay shape: a reader who stops generates nothing
that could reveal the reason was wrong.

frankh-3f's `--ro-rtti` (`48b75b34b`, off by default) marks class RTTI headers
and VMTs read-only. It deliberately does NOT mark the registry table, and **I
gave the wrong reason for that**: I told him the registry would fault by
construction, because its two pointer words per entry are filled by
`AddDataPtrFix` at emission. **That is wrong.** `AddDataPtrFix` patches the FILE
IMAGE, before the read-only pieces are permuted, so a span filled that way does
not fault. His proof is direct and is the kind that settles it: the blob headers
are filled by **exactly the same `AddDataPtrFix` calls**, they ARE marked
read-only under the flag, and `test_ro_rtti_write`'s plain row runs clean with
`ClassName` and `is` both reading them.

**So the registry is excluded because it was SCOPED OUT, and whether anything
writes it at run time is simply unmeasured.** Nobody should read the exclusion
as evidence. Measuring it is one line of `RoRangeAdd` over the table's span plus
a run, and the answer is worth having before anyone treats the registry as
immutable.

His positive control is the one this ticket asked for and it fires: a store into
a VMT slot and a store into an RTTI header, each reached through an instance,
fault with rc=139 under the flag and land without it.

**The self-host with the flag defaulted on is WEAK evidence and must not be
quoted as a sweep** — frankh-3f's own correction of a line I wrote, and it is
CLAUDE.md's stated scope limit on the fixedpoint arriving in a live case: *it
cannot see a construct the compiler never writes.* `compiler.pas` is a
deliberately procedural subset that declares no classes of its own, so the only
VMT and RTTI header in its image belong to the builtin `TObject`. A converged
2-round self-host shows the compiler still runs with those two spans read-only
and exercises almost no class RTTI path. **I had claimed it was a stronger sweep
than test-core, on the reasoning that `compiler.pas` walks paths no fixture
does. That is true of parser and IR paths and false of exactly this one.** The
evidence is `test-core`.

### BUILT 2026-09-19 (frankB) — THE REGISTRY IS NOW CONDITIONAL ON ITS READER

The step the park note named is done. `RTTIRegRequested` is set at the two
`AN_RTTI_REG` creation sites (`pasparser_expr.inc`, `pyparser.inc`) and read by
`EmitRTTI`, which now emits the registry only when `(regEntries > 0) and
RTTIRegRequested`.

**Why the flag is set at PARSE time and not at the lowering site, where it
belongs:** `EmitRTTI` runs immediately after the parse and **before any IR
lowering**, so `ir.inc`'s `AN_RTTI_REG -> IR_RTTI_REG` arm — which would have
been one site instead of two, and free for every future frontend — fires too
late to be read. The consequence is that the flag is conservative: a
`__rttireg()` in code that is never lowered still emits the registry. Wrong in
the direction that keeps working.

**MEASURED, against an expectation recorded before the change rather than
after:** predicted a hello would lose exactly 24 bytes (8-byte count slot + one
16-byte entry) and a GetClass program exactly 0. Both landed:
`data=4288B -> 4264B` and `data=10360B -> 10360B`, with the GetClass program
still printing FOUND.

**THE 24 BYTES ARE NOT THE POINT AND MUST NOT TRAVEL AS THE WIN.** This does not
drop a single blob: Pass 1 still reserves a header per class, because `ClassName`
and the `is`/`as` backlink chain need one. What it removes is the unconditional
ROOT — while the registry was emitted regardless, it held every streamable class
alive BY NAME, and every ordinary class is streamable. A reachability-gated drop
was impossible before this and is merely unwritten after it.

**AND IT NEVER FIRES FOR NILPY, WHICH IS A POPULATION FACT AND NOT A BUG.**
Measured: `print(1)` alone reports `reader=1`. Every NilPy program pulls
`pylib`, and `compiler/builtin/pylib.pas:40` reads
`uses builtin, exceptions, pypal, promocore, typinfo` — `typinfo.pas:755` is
`reg := __rttireg()`. So a NilPy program always contains a reader by
construction and saves nothing here. **A NilPy-side saving would have to come
from making that `uses typinfo` conditional, which is Track N's ground and is
not claimed by this ticket.** Recorded so the next reader does not measure a
Pascal-only number and quote it for both frontends.

**AND IT REACHES THE ESP UMBRELLA, which is the consequence this note stopped
one step short of.** The SRAM case for this whole line of work is weaker on
NilPy than on Pascal, and weaker by construction rather than by degree: a NilPy
image on ESP carries the registry — and therefore the name-root on every
streamable class — no matter what the program does, until that `uses` is
conditional. So a future reachability pass measured on a Pascal ESP image and
quoted for the ESP target generally would be the population error this ticket
has already made once today in the other direction. **Measure both frontends or
name the one you measured.**

**AND THE FIX FOR IT IS NOT A CALL-SITE PREDICATE, WHICH IS WORTH RECORDING
BECAUSE IT IS THE OBVIOUS ANSWER AND IT IS WRONG.** Measured 2026-09-19: a
Pascal program with `uses typinfo` that NEVER calls `GetClass` reports
`reader=1 registry=2 registrybytes=40`; the identical program without the
`uses` reports `reader=0 registry=0 registrybytes=0`. The flag is a parse-time
fact, so **merely parsing `typinfo` mints a reader** — making `GetClass`
conditional, or teaching the builtin chain which routines a program actually
called, would leave this gate exactly where it is. Only the `uses` going helps.

**Census of the chain, read-only, handed to franks-ee who owns it:** it is TWO
ambient sites, not one — `pylib.pas:40` and `pyeval.pas:47` both pull typinfo —
and **typinfo is doubling as a TYPES unit**, which is why no conditional keyed
on "does this program reflect" can be correct: `streams.pas:12` is
`uses typinfo; { PUInt8 }` and `resources.pas:11` is
`uses typinfo; { PString — declaring it here too would duplicate the type and
corrupt RTTI }`. The two NilPy units are in the same position, wanting the RTTI
TYPES rather than the reflection surface (pylib references `PClassRTTI` 29
times and `GetInstanceRTTI` 25; pyeval 13 and 9), and neither calls `GetClass`
or `__rttireg` itself. **Hypothesis, NOT a recommendation and not costed:** the
answer may be to split the unit — types one side, `GetClass`/`FindClass`/
`__rttireg` the other — at which point the chain pulls only the types half and
no reflection predicate is needed by anyone. Owned by franks-ee, who has the
corpus; this ticket claims none of it.

**THE SPLIT IS FULLY ANALYSED AND DELIBERATELY NOT BUILT — census by franks-ee
2026-09-19, verified here, DECLINED on price.** The shape is smaller and
cleaner than the hypothesis above: it is not "types vs reflection", it is
**move `GetClass` into its own unit**. `typinfo` has NO `uses` clause and NO
`initialization`/`finalization` section, so there is nothing transitive and
nothing kept alive by an initializer; property access by name works off a
class's own RTTI pointer and not off the registry, so every other piece of
reflection stays put — including the `PUInt8`/`PString` users (`streams.pas:12`,
`resources.pas:11`) and the RTTI types `pylib` and `pyeval` lean on. The `uses`
rewrite is four files, **none on the NilPy ambient chain**: `classes_lite.pas`
(2 call sites), `lfm.pas` (1), `gtk3widgets.pas` (8), `controls.pas` (1). `pylib`
and `pyeval` call `GetClass` ZERO times. **No Track U fork is needed**, because
the line is "the class registry lookup" and not "reflection", so nobody has to
decide what `typinfo` IS.

**ONE CORRECTION TO THAT CENSUS, because it narrows a claim someone will
otherwise over-apply:** `__rttireg` is called at **THREE** sites, not one —
`typinfo.pas:755`, `controls.pas:167`, `gtk3widgets.pas:286`. Moving `GetClass`
takes the reader away from a **NilPy** program, because the other two are pcl
and not on that chain; a **GUI** program still mints one from either of them
after the split. "Move GetClass and the reader goes" is true of the population
in question and false in general.

**DECLINED, and the reason is the price and not the shape:** ~24-40 bytes
direct, against a new unit plus a `uses` rewrite across `lib/rtl` and `lib/pcl`,
which is Track B's ground. Its real value is as a SECOND enabler for the
reachability pass — the same value as this gate — and that pass is still
unwritten. Building a second enabler for something that does not exist is how a
backlog becomes a queue. The analysis is banked here so the split is a same-day
change once the pass lands.

**AND THE VERIFICATION THAT MUST HAPPEN FIRST IS RECORDED UNRUN, labelled
rather than quietly omitted.** This ticket has MEASURED that parsing `typinfo`
mints a reader; it has NOT measured that the `__rttireg()` CALL is what does it.
Those are "consistent with" and not the same claim. Before any `lib/rtl` edit:
copy `typinfo` to a scratch dir, stub `GetClass` so the `__rttireg()` call goes,
compile with `-Fu` against the copy, read `reader=`. Zero means the call is the
trigger. **Non-zero is also a result** — it means the reader enters somewhere
neither seat has looked, and `reader=` is the instrument that would say so. Ten
minutes, and it must precede the edit rather than follow it.

**The instrument grew two columns to make this observable**, and they are
deliberately separate: `reader=` is the parse-time fact, `registry=` is what the
emitter did. Collapsed into one they could not distinguish "the gate dropped it"
from "the program never asked", which is exactly the distinction under test.
The legitimate third state — `reader=1 registry=0`, a program that calls
GetClass but declares no streamable class — is not a defect and returns nil
correctly.

**The `test-core` row's positive control is the PAIR and both halves were
verified to FAIL, not assumed to:** the pinned compiler (no gate at all) fails
the no-reader row with its own message, and a deliberately over-firing gate
(`and (1 = 2)` spliced in, built, run, reverted, binary restored
byte-identically to `c4562f4bf4db`) fails the reader row with its own. The
reader row asserts the RUNTIME lookup as well as the byte count, because a
registry that is emitted but wrong satisfies any count.

**What the silent `DATAREF_DROP` defect does under this change: nothing new, and
that was checked rather than assumed.** A program now lacking a registry also
lacks a reader by construction of the gate, so the (reader, no-registry) pairing
that reaches `DATAREF_DROP` is the same set as before — `regEntries = 0` with a
reader — and it answers nil correctly. The defect is untouched and still owned
by whoever makes the next change in that predicate.

### PARKED 2026-09-18 (frankB) — WHERE A COLD SEAT PICKS THIS UP

**Nothing is half-landed. The pass was deliberately never started**, because the
measurement below relocates the ticket rather than sizing it. What is banked is
the instrument, the boundary, and one fixed bug found while pricing it.

**The next step is ONE change and it is not the one this ticket's title asks
for:** make the RTTI registry conditional on the `AN_RTTI_REG` **node** rather
than emitting it whenever any class is streamable. Concretely, in
`compiler/rtti_emit.inc` at the `if regEntries > 0 then` arm (the block that
sets `RTTIRegistryOff`), gate on whether the program actually contains an
`AN_RTTI_REG` node. **Do NOT gate on `uses typinfo`** — `__rttireg()` is a
public intrinsic a user program can call directly, and a hand-maintained union
of unit names is the exact failure the frontend-cannot-see ticket records from
the other side.

**Why that is the lever and the ticket's own proposal is not:** every ordinary
class is registry-rooted (no visibility keyword defaults to `published`), so a
reachability-gated drop finds almost nothing to drop while the registry is an
unconditional root. Make the root conditional and the residue becomes droppable.
Only then is the pass this ticket describes worth writing.

**Three things already closed, so do not redo them:**
- The `--emit-obj` edge is MOOT, measured: each object carries its own `Data[]`
  and its own registry, so cross-object `GetClass` does not work today
  (`a=1 B_finds_A=0 B_finds_its_own=1`) and node-conditional emission cannot
  break it. No `--emit-obj` arm is needed.
- The registry's sole consumer is `IR_RTTI_REG`, verified across all six
  backends; inside `lib/` the intrinsic is called from three files only
  (`rtl/typinfo.pas` GetClass, `pcl/controls.pas`, `pcl/gtk3widgets.pas`).
- The keying bug below is FIXED and has a test row; it is not outstanding work.

**One defect found and deliberately NOT fixed, because whoever writes the gate
will be changing that exact predicate:** `emit.inc` sets `DATAREF_DROP` when
there is no registry and the intrinsic then reads nil. A registry with no reader
gives no diagnostic and a reader with no registry gives no refusal — the
silent-negative shape, and the reason an emitted-and-never-read registry went
unnoticed. **Decide what a node-conditional registry should do there before
writing the gate, not after.**

**Also parked, and it is frankh-3f's suggestion rather than a finding:** a
`RoRangeCount` snapshot + `ErrorNoPos` guard around the blob and VMT emitters,
his `1cdb560f4` shape. By his own framing the RTTI rows are green and no emitter
is known to intern mid-blob, so it makes the FIRST offender loud rather than
fixing a live defect — which means **it has no natural positive control**.
Whoever adds it owes a manufactured one (an emitter with a deliberate mid-blob
intern, asserted to fire, then removed) or a finding that `RoRangeCount`
structurally cannot move in that span.

**Ownership, settled with frankh-3f and still live:** whether a blob is EMITTED
is this ticket's; where a survivor LIVES is his (`c44fa2642`, ESP-IDF `.rodata`
in both ELF32 object writers). His half is unblocked and does not need the
registry gate first — the gate only decides whether there is ALSO a droppable
set on top.

### A LIVE BUG FOUND IN THE REGISTRY EMITTER WHILE PRICING IT, AND FIXED

Chasing frankh-3f's mid-blob-intern hazard into this loop turned up a different
defect in the same four lines. The registry is a count slot followed by fixed
16-byte `(name ptr, rtti ptr)` pairs, and it interned **the raw `TokSliceStr`
declaration spelling** for the name key. Pass 2 interns `ClassRttiName(ci)`,
which is **canonical for a specialization alias**. For every ordinary class the
two strings are identical — which is exactly why this survived: the divergence
needs a specialization.

Measured on the pinned compiler, `stable_linux_amd64/default/pinned`:

    ClassName=TBox<System.LongInt>
    GetClass(b.ClassName)   MISSING
    GetClass('TIntBox')     FOUND

**The one round trip the registry exists for fails, and a lookup under a name no
instance ever reports succeeds.** Every streaming path does
`GetClass(X.ClassName)`.

Fixed by interning `ClassRttiName(ci)` here as well. It also closes the route to
frankh-3f's hazard rather than leaving it resting on an ordering nobody states:
`ClassRttiName` is guaranteed already-interned by Pass 2, so `InternStr` here can
never append and push later entries off the 16-byte stride; the raw spelling
carried no such guarantee. **The layout hazard itself did NOT reproduce** — three
streamable classes, all three found — so that half stays a removed route, not a
fixed bug.

**The positive control is the pin, not something manufactured**, and the third
row is what makes it a control: `plain-class-control` is FOUND on BOTH compilers.
Without it, a registry that found *nothing* would satisfy the MISSING assertion
and the row would certify a completely broken registry. Wired into `test-core` as
`test/test_rtti_registry_is_keyed_by_classname.pas`.

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

**AND THE SECOND RULE IS ABOUT WHEN, NOT ABOUT WHAT — DO NOT INTERN A STRING
BETWEEN A CONTIGUOUS STRUCTURE'S FIRST AND LAST BYTE.** frankh-3f, `1cdb560f4`:
`ResolveSynthImportLibraries` interned a soname into `.dynstr` *while* that
table was being built, the read-only split moved those 48 bytes out and closed
the gap, and `DT_NEEDED` read `>`.

**Corrected by frankh-3f, and the correction widens it rather than narrowing
it — my first note here had the mechanism wrong.** I wrote that the hazard was
to self-relative words. It is not: `typeRef`/`baseTypeRef` are `target - pos`
and `AddDataRelFix` records them, so they survive a mid-blob intern intact.
The real hazard needs no offsets in the blob at all. **Any contiguous RW
structure read as `base + fixed offset` is CUT IN TWO if `InternStr` runs
between its first and last byte** — the split hoists the literal out, the gap
closes, and every field after the cut shifts by the literal's size. `.dynstr`
was one instance; an RTTI blob is another, and so is any record image a future
pass builds in one span.

**AND IF A BLOB EVER BECOMES READ-ONLY, THE IRAM EXCLUSION DOES NOT COVER A READ
THROUGH A POINTER.** frankh-3f, `c44fa2642` (ESP-IDF `.rodata` in both ELF32
object writers; `rtti_emit.inc` untouched, the five relfix sites re-patched per
object by the new `ObjRoPrepare`, and both ends of a relative word must share a
section or `ErrorNoPos`). Measured there: `test_emit_obj.pas` on xtensa, SRAM
`.data` 6304 -> 2624 B. The caveat that lands on this ticket: an IRAM-safe ISR
runs with the **flash cache off**, so a literal an `iram;` routine references
DIRECTLY is deliberately kept in `.data` by `ObjRoKeepIramLiteralsWritable` —
but that exclusion sees **Fixups from iram code only**. A VMT or RTTI blob
reached through a POINTER from an `iram;` method is invisible to it, and would
be flash-mapped and unreadable exactly when the ISR runs. So "this blob is never
written" is NOT sufficient to justify moving it; the second question is whether
any `iram;` code can reach it, and today nothing answers that.

**The guard is cheap and it is in this ticket's file:** snapshot `RoRangeCount`
when a blob starts and `ErrorNoPos` if it has changed at the end — `1cdb560f4`'s
own shape, suggested for the blob and VMT emitters in `rtti_emit.inc`. NOT YET
BUILT, and the honest status is that there is no known offender: the RTTI rows
are green, so this makes the FIRST one loud rather than fixing a live defect.
Whoever adds it owes it a positive control — an emitter with a deliberate
mid-blob intern, asserted to fire — because a guard nothing can trip is a guard
that prints PASS.

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

## Parked 2026-09-19

Registry root removed in 5bde993c5 -- the one blocker is gone and the pass itself is now writable and unwritten. Parked rather than held: my group is closed and a ticket sitting in working/ with an owner who is not working it misroutes the next reader. Read the BUILT 2026-09-19 and PARKED 2026-09-18 sections in the body before starting; they name what is already closed (the --emit-obj edge, the registry's single consumer, the keying bug) so none of it is redone, and the silent DATAREF_DROP defect that whoever writes the pass will be editing anyway.

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

## 2026-09-20 (frankS) — the largest remaining rung of the ESP umbrella, written up so the next seat needs nothing from me

Once the eval() interpreter stopped being linked
([[bug-a-a-static-nilpy-program-links-the-runtime-eval-interpreter]], −52%),
this became the top root of what is left. Everything below is from
`--dce-why` on `examples/esp32/nilpy-c3/main/main.npy`, xtensa windowed,
`--platform=esp --no-signals --dce`, at `857dcdaac`. **Re-measure before
quoting: the population is one program on one ISA.**

### The shape of what is left

| first reason | bytes | bodies |
| --- | ---: | ---: |
| called by (an ordinary call edge) | 639,962 | 340 |
| **vmt/rtti slot** | **172,637** | **149** |
| @proc taken in unowned code | 13,725 | 2 |
| called from unowned code | 1,006 | 5 |
| total live | 827,330 | |

The two `@proc` rows are pyeval's unconditional `PyIterCallHook := @PyCallKey1`
install and **stay by design** — a lazy install is
`bug-nilpy-min-max-with-a-key-held-in-a-variable-picks-the-numeric-overload`.
Do not treat them as a target.

### The chains, which is the part that is new

```
94665B  pyiter_has <- pyiter_drain <- pyseq_of_obj <- TPyFile.writelines <- [vmt/rtti slot]
12761B  TPyBytes.decode <- [vmt/rtti slot]
12161B  PyUserArithCallMeth <- pyiter_has <- ... <- TPyFile.writelines <- [vmt/rtti slot]
10581B  pyvar_gt <- TPyList.sort <- [vmt/rtti slot]
 8780B  pyfloat_parse <- pyiter_has <- ... <- TPyFile.writelines <- [vmt/rtti slot]
 8393B  PyVarEq <- TPyDict.indexof <- [vmt/rtti slot]
 5903B  TPyList.sort <- [vmt/rtti slot]
 5801B  TPyDict.most_common <- [vmt/rtti slot]
 5111B  TPyDict.update <- [vmt/rtti slot]
```

**One method, `TPyFile.writelines`, heads three of the nine largest rows —
115,606 B between them, in a program that never opens a file.** It accepts any
sequence, so it pulls `pyseq_of_obj` and the whole iterator-drain path behind
it. Nothing calls it; it is in the VMT because `TPyFile` has one.

### What this says about the CRITERION, and it is not what the title assumes

The title says *unreferenced class* RTTI. **These classes are all legitimately
live** — the program really does use `TPyList`, `TPyDict`, `TPyFile`. A
per-CLASS criterion therefore reaches none of this. What costs is a **per-METHOD
slot nothing can dispatch to**: `writelines`, `decode`, `most_common`, `update`
are individually unreachable on a live class.

So the design question for whoever takes this is devirtualisation-shaped, not
emission-shaped: **when can a VMT slot be proven undispatchable?** A method
whose name is never used in a dynamic attribute lookup, never overridden, and
never reached by `getattr`, is a candidate. `PyUserObjGetattr` and
`pydynattr_get_v` are live in this very image, which is what makes the
conservative answer conservative — that is the thing to establish first, not
the savings.

### What the instrument already answers, and what it does NOT

- `--dce-why` gives the per-reason table and the twenty biggest bodies with
  chains. `--dce-why=<substring>` names any body you name, live or `DROPPED`,
  with its chain — so you can test a candidate in one command rather than
  rebuilding.
- **It does NOT total a subtree.** The 115,606 B above is the sum of three rows
  that happen to be in the top twenty; the true amount `TPyFile.writelines`
  drags is larger and nothing reports it. **A per-root subtree total is the
  missing instrument here**, and it is the same "nothing answers HOW MUCH"
  hole the umbrella already names. Build that before ranking candidates
  against each other.
- Attribution is FIRST-reason, so a body reachable both by a call and through a
  VMT slot is counted once, under whichever came first. Reading the vmt total
  as "what would be freed" is wrong in both directions.


## 2026-09-22 (frankb-8e) — re-measured as instructed, and the headline bucket contains `main`

frankS's handover says *"Re-measure before quoting: the population is one program
on one ISA."* Done, same program, same ISA, at `fc53bd2bd`.

**THE RECORDED COMMAND DOES NOT BUILD AT HEAD.** The write-up above says
`--platform=esp --no-signals --dce`, xtensa windowed. At HEAD that fails twice
before it produces a number, and the second failure names its own remedy:

```
--target=xtensa --platform=esp --no-signals --dce --dce-why
  -> error: addi immediate displacement 128 is outside the encodable range   (Call0)
--target=xtensa --xtensa-abi=windowed --platform=esp --no-signals --dce --dce-why
  -> error: the forward call to PyUtf8CpAt at 475492 cannot reach its body at
     1081716 (CALL0/CALL8 reach +-512 KiB) ... Rebuild with --xtensa-long-calls
```

The command that reproduces is therefore

```
./compiler/pascal26 --target=xtensa --xtensa-abi=windowed --xtensa-long-calls \
  --platform=esp --no-signals --dce --dce-why \
  examples/esp32/nilpy-c3/main/main.npy <out>
```

Recorded here because a number whose command is not beside it is not
re-derivable, and this one is not re-derivable even by the same instrument on
the same file. I have NOT established whether the image crossed the ±512 KiB
forward-call threshold since `857dcdaac` or whether the flag was simply omitted
from the write-up; the error is a size threshold with a documented remedy, not
a defect, so I did not chase it.

### The table, both rows carried

| first reason | @`857dcdaac` (frankS) | @`fc53bd2bd` (me) |
| --- | ---: | ---: |
| called by | 639,962 B / 340 | 644,311 B / 340 |
| **vmt/rtti slot** | **172,637 B / 149** | **174,350 B / 149** |
| @proc taken in unowned code | 13,725 / 2 | 13,725 / 2 |
| called from unowned code | 1,006 / 5 | 1,006 / 5 |
| total live | 827,330 | 833,392 |

**Identical body counts in every bucket**, bytes up ~0.7%. That is two weeks of
code growth, not a structural change: the finding holds exactly as written.
`TPyFile.writelines` still heads the largest row, 95,157 B (was 94,665).

### And the bucket contains the program's entry point

The section above warns that attribution is FIRST-reason and that *"reading the
vmt total as 'what would be freed' is wrong in both directions."* Here is the
instance, which I think is worth more than the warning because nobody argues
with a row:

```
   8741B  PyUserObjGetattr <- pydynattr_get_v <- main <- [vmt/rtti slot]
   8289B  main <- [vmt/rtti slot]
   6884B  pydynattr_get_v <- main <- [vmt/rtti slot]
```

Confirmed directly: `--dce-why=main` answers `[match] 8289B main <- [vmt/rtti
slot]`. **`main` is in the 174,350 B bucket.** Those three rows alone are
23,914 B, 13.7% of it, and nobody is going to propose deleting the entry point.

So the headline number is **not** an upper bound on a saving and must never be
quoted as one. That is also the sharpest argument for the instrument this
section asks for, and it changes its shape: **a per-root SUBTREE TOTAL would
be wrong for the same reason.** Summing a subtree counts every body once per
root that reaches it, and `main`'s subtree is reachable from the entry point
regardless. The question anyone actually wants answered is

> if this root were removed, how many bytes stop being live?

which is a **differential**, not a sum: live-set WITH the root minus live-set
WITHOUT it. It over-counts nothing, it cannot be confused with a subtree, and
it answers `0` for a root like `main` that something else reaches anyway —
which is the correct answer and the one a subtree sum cannot give.

## 2026-09-22 (frankb-8e) — BUILT: `--dce-cost`, and it inverts the ranking

The section above asks for a per-root subtree total and says to build it
*"before ranking candidates against each other."* Built — as a **differential**
rather than a subtree total, for the reason in the section before this one, and
the difference is not academic: **the two numbers invert the ranking of the top
three candidates.**

`--dce-cost=<substr>` marks twice. Once with the VMT/RTTI slots of every method
whose name matches withheld, then once for real, and it reports the difference
in live bodies and bytes. Withholding a root can only shrink the live set
(`DceMark` only ever sets), so the difference is exactly the set of bodies that
stop being live — no double counting, and no way to confuse it with a subtree.

### What the candidates actually cost

nilpy-c3, xtensa windowed, `--xtensa-abi=windowed --xtensa-long-calls
--platform=esp --no-signals --dce`, binary `48f69d2d285d`. The middle column is
what this ticket has been ranking on: the rows for that method in the
`--dce-why` top-twenty listing, added up.

| candidate | `--dce-why` rows | **actual cost** | bodies |
| --- | ---: | ---: | ---: |
| `TPyList.sort` | 17,116 B | **30,411 B** | 18 |
| `TPyBytes.decode` | 12,909 B | **22,978 B** | 9 |
| `TPyDict.update` | 5,143 B | **17,068 B** | 4 |
| `TPyFile.writelines` | **116,178 B** | **13,571 B** | 8 |
| `TPyDict.most_common` | 5,845 B | **6,008 B** | 2 |
| `TPyDict.indexof` | 8,521 B | **0 B** | 0 |
| `main` | 23,914 B | **0 B** | 0 |

**`TPyFile.writelines` is over-stated by 8.6x and is fourth, not first.** The
iterator-drain path it heads is reached by something else as well, so removing
its slot frees only what is uniquely behind it. `TPyList.sort` — mid-pack in the
listing — is the largest real candidate. `TPyDict.indexof` is credited 8,521 B
and costs **nothing at all**.

The listing also UNDER-states, and for a different reason: it shows the twenty
biggest bodies, so a candidate whose cost is spread over many small bodies is
invisible to it. `TPyDict.update` is 3.3x its listed rows.

So this ticket's headline sentence — *"`TPyFile.writelines` alone heads three of
the nine largest rows, 115,606 B, because it accepts any sequence"* — is a true
statement about the LISTING and not about a saving. Anyone who had started work
from it would have spent it on the fourth-biggest item.

### Costs are NOT additive, in either direction

| withheld | cost | sum of its named methods above |
| --- | ---: | ---: |
| `TPyList.*` | 70,544 B / 52 | 30,411 |
| `TPyDict.*` | 45,759 B / 23 | 23,076 |
| `TPyFile.*` | 31,637 B / 31 | 13,571 |

Withholding a whole class's slots frees **more** than the sum of withholding
each method alone, because bodies shared between two slots die only when both
go. So a per-candidate table is a guide to where to look and **never a plan**:
measure the union you actually intend to remove.

### `main` is the control and it answers zero

`main` is inside the 174,350 B `vmt/rtti slot` bucket (`--dce-why=main` says so)
and costs **0 B in 0 bodies**, because the entry root reaches it anyway. That is
the row no subtree sum can produce, and it is the reason the instrument is
subtraction rather than addition.

### Guarded

`test/test_dce_cost_is_a_differential_not_a_subtree_sum.pas`, wired into
`test-quick`, three rows asserted as BODY COUNTS so they do not drift with code
size: a slot that costs **2** bodies where a subtree sum would say three or
four; a live non-slot name that must cost **0**; and a virtual method that costs
exactly **1**, its own body. That third row was first written asserting zero,
from the argument that the method is "called" from two places — both of those
calls dispatch THROUGH the slot, so for a virtual method the slot is the only
edge there is. The measurement corrected the argument and the row keeps the
measured value.

### What this does NOT do

It does not say a slot is removable. It prices a candidate on the assumption
that the slot goes, which is the question the section above says to answer
first: **when can a VMT slot be proven undispatchable?** `PyUserObjGetattr` and
`pydynattr_get_v` are live in this image, and that is still the thing to
establish before any of these numbers become a saving. The instrument exists so
that whoever establishes it is working on `TPyList.sort` and not on
`TPyFile.writelines`.
