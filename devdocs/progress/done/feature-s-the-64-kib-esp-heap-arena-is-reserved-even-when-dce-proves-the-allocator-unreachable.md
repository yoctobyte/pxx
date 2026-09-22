---
prio: 60
track: S
type: feature
status: done
found: 2026-09-21
found-by: frankB
owner: frankh-c0
blocked-by: []
summary: "DONE 2026-09-22. EspArena was 65,536 B of BSS reserved for any bare-ESP program that LINKS builtinheap, including one where DCE had proved every allocator entry point dead; it is now dropped when `HeapMmap` -- its only reader in the whole tree -- does not survive DCE. PREDICATE IS ONE PROC AND IS THE TRUE REFERENT, not a proxy: EspArena is referenced from exactly one place, builtinheap.pas:1306 inside HeapMmap, so `can anything read the arena` IS `is HeapMmap live`, with no allocator list to go stale. IMPLEMENTED AS A REMAP, NOT A REWRITE, on frankz-e5's reading of the RoRange*/DataRemap precedent: BssRemap(o) beside DataRemap(o) in elfwriter.inc, identity unless a hole was punched, so stored offsets never change and nothing that recorded one has to know the hole exists. That dissolved a hazard NEITHER of us had enumerated -- BSS_SIG_ALTSTK, BSS_INTBUF and XtExcSlotOff are allocated during CODEGEN and therefore sit ABOVE a Pascal unit global, so an in-place rewrite of Syms/GlobFix would have had to reason about each; under a remap they shift with everything else, which is simply correct. TWO call sites, not one: ApplyImageFixups and a second inside writeELF32, which is the writer riscv32 and xtensa actually use -- patching only the 64-bit one would have been a change that does nothing on the targets it is for, and an edit tool refusing for ambiguity is the only reason I looked. MEASURED esp32c3 bare, one program each: frozen-string-constant 66,812 -> 1,276 B bss (-65,536, 98.1%); string[16] 66,832 -> 1,296 B; SetLength control correctly keeps 66,812 B because HeapMmap is live; --no-dce keeps it in all three, which is the positive control. VERIFIED RUNNING, not just sized: a bare program carrying three scalar globals and an array global -- all ABOVE the arena and shifted by the remap -- matches the x86-64 oracle byte-for-byte under qemu on esp32c3 AND esp32s3; wrong remap arithmetic prints garbage there rather than failing to build. make test-esp-bare 21 ok / 1 fail, identical to the pre-change baseline (the fail is the unrelated record-by-value regression). Gated on DceEnabled and that is load-bearing: DceRun exits at its first line when DCE is off, leaving DceLive unallocated, so every entry reads `not live` and the predicate would drop an arena the program is about to use. NOT CHECKED, bounded rather than cleared: composition with RoSplitActive, and the ESP object-writer path; BssDropLen is 0 for every target and profile but bare-ESP-with-dead-HeapMmap. THE WIN IS NARROW AND HONEST: nothing for a program that allocates, and the paying population is programs that LINK builtinheap for a non-allocating reason -- one frozen string constant is enough. The layer that fixes that is feature-a-pull-builtinheap-on-demand-instead-of-predicting-it."
---

# The 64 KiB ESP heap arena is reserved even when DCE proves the allocator unreachable

## Measured AT HEAD, 2026-09-22 -- and the original witness no longer fires

`compiler/builtin/builtinheap.pas:1155`, inside `{$ifdef PXX_ESP}`:

    EspArena     : array[0..(HEAP_ARENA div 8) - 1] of Int64;

with `HEAP_ARENA = 65536` by default.

**THE WITNESS THIS TICKET WAS FILED WITH HAS GONE STALE, AND IT GOES STALE IN
THE DIRECTION THAT READS AS FIXED.** It said *an empty bare program*. At HEAD an
empty bare program pays **640 B**, not 66,808 B, because it links no heap unit
at all (`procs=16`). A reader reproducing the ticket as written gets a clean
result and files it `rejected/`. The MECHANISM was never wrong; the row was.

Binary `464ddd6c2b02`, tree `f35b44b8b`, `--esp-profile=bare --target=esp32c3`,
one program per row, each compiled from a clean tree:

| program | what it does | code | bss | procs |
| --- | --- | --- | --- | --- |
| `empty` | `begin end.` | 20 B | **640 B** | 16 |
| `rec` | two Integer fields in a record | 440 B | **652 B** | 17 |
| `noalloc` | a `for` loop over Integers | 616 B | **652 B** | 17 |
| `frozen` | `p := MSG`, one frozen string constant | 524 B | **66,812 B** | 85 |
| `strvar` | one `string[16]` | 536 B | **66,832 B** | 85 |
| `alloc` | `SetLength(a, 8)` | 39,352 B | 66,812 B | 85 |

**The live shape is `frozen`**, and it is six lines:

    program frozen;
    const MSG = 'hi';
    var p: PChar;
    begin
      p := MSG;
      if p = nil then Halt(1);
    end.

    dce: bodies 81  live 2 (160B)  dead 78 (89268B)  dropping 78 (89268B)
    dce: code 89792B -> 524B
    ok: [code=524B  data=360B  bss=66812B  procs=85]

**524 B of code, 66,812 B of BSS.** DCE removes 99.4% of the code it was handed,
every allocator entry point included, and the arena is reserved anyway: 65,536 of
66,812 B is **98.1% of the program's BSS**, and the arena is **125x the size of
the program it serves**. `strvar` is the same thing through a second door.

Note the boundary the table draws, because it is the useful part: the arena
arrives with **builtinheap being linked at all** (`procs` 17 -> 85), not with
allocation. `alloc` pays the same 66,812 B as `frozen` and actually uses it.
`noalloc` pays nothing. So the population is not "programs that do not allocate"
-- it is **programs that link the heap unit for a non-allocating reason**, and a
frozen string constant is enough to do that.

## A measurement note against myself: the numbers I took first were void

My first pass at this ticket reported `code=336B bss=66808B procs=85` for an
EMPTY program and I nearly wrote it up. The binary on disk was the crippled one
my own bisect script leaves behind on NORMAL completion -- it restores the
source and never rebuilds, and `compiler/pascal26` is untracked, so `git status`
is silent about it. `sha256sum` said `fda77c48b8ee`; a rebuild `converged` to
`464ddd6c2b02`.

**What makes this worth a paragraph is that the crippled binary's BSS figure was
66,808 B against the true 66,812 B.** Four bytes out, on the number the ticket
turns on -- and it MATCHED the filed figure exactly, so it read as
corroboration of the original measurement rather than as a broken instrument.
The code figure (336 B vs 524 B) was the only row that disagreed, and it is the
row nobody checks. CLAUDE.md's "every instrument that lies, lies by being
CORRECT ABOUT SOMETHING ELSE", with the sharpening that the something-else can
be *almost exactly the right answer on the axis you care about*.

## Why the alt-stack pattern does NOT transfer, which is the whole difficulty

This ticket was filed expecting `16ebf18ce`'s shape to apply. It does not, and
the reason is structural rather than a matter of effort:

- The **alt stack** is reserved BY THE COMPILER -- `Inc(BSSSize, SIG_ALTSTACK_SIZE)`
  at one site in `ir_codegen.inc` (~1455-1490), under `SigAltStackAllocated` and
  gated by `TargetHasSignalRuntime`. One predicate, one place, *reserved iff
  emitted*.
- **`EspArena` is an ordinary Pascal unit global.** Its BSS comes from
  `AllocateSymOffset` (`ast_syminfer.inc:163-165`) like every other `skGlobal`
  sym, at PARSE time -- long before DCE runs. There is no compiler-side
  reservation site to gate.

And the gap behind that: **DCE does not eliminate dead globals at all.** It
compacts `GlobFix`/`GlobFixPCRel` relocations after code is dropped, and that is
the only thing in `dce.inc` that touches globals. A global whose every referring
body has been dropped keeps its BSS.

So there are two routes, and they are different sizes:

1. **Dead-global elimination** (general). After DCE, a `skGlobal` named by no
   surviving body's fixups is dead. Reclaiming an INTERIOR one means recompacting
   BSS and rewriting every `GlobFix` offset -- mechanical, since DCE already
   rewrites fixups, but it is a real feature and it is not arena-specific.
   Hazards: any global whose address is taken by a route not in `GlobFix`.
2. **Move the arena to a compiler-reserved block** on the `BSS_HEAP_PTR` /
   `BSS_INITIAL_RSP` pattern (`pasparser_prog.inc:1099-1100`), reserved after DCE
   and only if an allocator body survived. This restores the alt stack's shape
   exactly, at the cost of `HeapMmap` getting its base from a compiler-provided
   slot instead of `@EspArena[0]`.

Route 2 is the smaller change and matches an existing idiom; route 1 is worth
more and is a separate ticket. **Neither is started.**

## ROUTE 2 IS SETTLED AND THE PIECES ALL EXIST — measured 2026-09-22

Three facts, each read off the tree rather than reasoned:

**1. The arena is INTERIOR to BSS, so the cheap version is dead.** Ambient units
are parsed at `pasparser_prog.inc` ~2085-2180 (`ParseUsesUnitAmbient`), and the
program's own `tkVar: ParseVarSection` is at 2360. Builtin globals therefore get
LOW offsets and user globals follow — confirmed by adding a 4,096 B global to the
`frozen` witness, `bss` 66,812 -> 70,912. So "shrink `BSSSize` if the dead range
is a suffix" cannot work: a single user global sits after the arena.

**2. `DceRun` runs late, and the tree already reserves space after it FOR THIS
EXACT REASON.** `compiler.pas:3020`, *"after every emitter (RTTI included), before
anything reads a final code offset"*. Immediately below it,
`EmitBareVectorTableAfterDce`, whose comment is the design note for route 2
written by somebody else for a different object:

> *"AFTER DceRun, and that is the whole reason it is here ... DCE removes bytes
> ahead of it — so aligning it while parsing aligns it to a layout that no longer
> exists by the time anything reads it. Emitted last, when nothing moves again,
> its offset is final by construction rather than by repair."*

A compiler-reserved arena allocated after `DceRun` has a final offset by
construction and shifts nothing, because nothing is behind it.

**3. NO NEW INTRINSIC IS NEEDED, which was the expensive part of route 2 and it
evaporates.** `frontend_prologue.inc:113-117` shows the compiler ALREADY
reserving a heap arena exactly this way, gated on `EspBareBoot`:

    if EspBareBoot then
    begin
      BSS_HEAP_ARENA := BSSSize;
      Inc(BSSSize, SocNilPyArenaSize(TargetSoc));
    end;

That is e5's `f028632c3` casualty — removed because it was dead, not because the
mechanism was wrong. And the mechanism's own dead-code note records how the
Pascal side reached it: **the ENTRY STUB wrote `HeapPtr`/`HeapEnd` into BSS from
the arena base, and the native allocator read those.** So `HeapMmap` never needs
the base directly and `__pxxTlsBase`-style plumbing is not required.

### The shape, then

- Stop declaring `EspArena` in `builtinheap.pas` for the bare profile; let the
  `{$else}` arm's `HeapPtr`/`HeapEnd` path serve it, as the NilPy arena did.
- Reserve `HEAP_ARENA` bytes of BSS **after `DceRun`**, gated on whether any
  allocator body survived, on the `EmitBareVectorTableAfterDce` pattern.
- Entry stub seeds `HeapPtr`/`HeapEnd` from that base.

**The predicate is the one open question I have not measured**: what exactly to
ask after `DceRun` for "did any allocator body survive". `--dce-why` already
distinguishes the cases (`frozen` drops all 78; `alloc` keeps them), so the
information exists; whether it is still addressable at that point in
`compiler.pas` is unchecked. **Do not write the guard from this paragraph** —
re-derive the predicate from the tree, per the born-red rule.

### Not to be fixed here: the pre-scan

It is tempting to make `frozen` stop linking `builtinheap` at all — the arena
arrives with the unit, so narrowing the token pre-scan would make this witness
go away. **Do not.** Two reasons. `pasparser_prog.inc` ~352-360 says the scan
deliberately does not try to tell frozen from managed, having measured that a
frozen string still needs the bundle's concat and write helpers. And
**`frankb-8e` has a 234-line patch parked on `needsAnsiRuntime`** — that is one
QUESTION with two seats on it, which is the collision git cannot see. The arena
fix belongs on the BSS side and does not touch the scan.

 The sharp edge named below
-- the predicate must be evaluated where the arena is declared, not where it is
first read (`12d6c86f0`) -- applies to route 2 directly.

## IMPLEMENTED 2026-09-22 — and the route is neither of the two above

Landed as a **remap**, not as a reservation and not as an in-place rewrite. The
shape is `frankz-e5`'s: it pointed at `RoRange*`/`DataRemap`, which solves the
same problem for `Data[]`, and the borrowed part is the invariant rather than
the code (`defs.inc`, verbatim): *"Offsets everywhere else stay in `Data[]`
coordinates: fixups resolve through `DataRemap`, so nothing that records an
offset has to know the split exists."*

Three edits:

- `defs.inc` — `BssDropOff`, `BssDropLen`. Zero means no hole, which is every
  target and every profile but one.
- `elfwriter.inc` — `BssRemap(o)` beside `DataRemap(o)`, and **two** call sites:
  `ApplyImageFixups` and a second inside `writeELF32`. The 32-bit writer is the
  one riscv32 and xtensa actually use, so patching only the 64-bit one would
  have been a change that does nothing on the targets it is for.
- `dce.inc` — `DropEspArenaIfAllocatorDead`, called from `compiler.pas` directly
  after `DceRun`.

### Why not route 1 or route 2

Route 1 (rewrite `Syms` and `GlobFix` offsets in place) has two bugs available
that a remap cannot have: it must get right WHICH stored offsets are BSS, since
`GlobFix` packs data offsets into the same field (`SymOffIsData`), and it
acquires a dependency on nothing having captured a BSS address before the
rewrite.

**And the hazard that actually decided it was one I had not enumerated.**
`BSS_SIG_ALTSTK`, `BSS_INTBUF`, `XtExcSlotOff` and the rest are allocated during
CODEGEN, so they sit ABOVE a Pascal unit global. An in-place rewrite would have
had to reason about each; under a remap they shift with everything else, which
is simply correct. The hazard I *had* written down — a BSS address resolved into
`.data` before `DceRun` — does not exist: `Fixups[]` are `Data[]` coordinates
only.

### The completeness condition, verified rather than assumed

`EmitGlobRef` (`emit.inc:1150`) is the single funnel for emitting a BSS address;
the per-backend helpers go through it (`EmitLoadGlobAddrRISCV32` ->
`EmitGlobRef`); and `bssBase + GlobFix[i].BSSoff` is the only expression that
forms a BSS address from an offset. Compiler slots and Pascal globals alike.

### The predicate

`HeapMmap` is not live. One proc, and the **true referent** rather than a proxy:
`EspArena` is referenced from exactly one place in the tree, and `EspArenaUsed`
only from two more in the same function. Same predicate the NilPy arena ticket
used, reached independently.

**Gated on `DceEnabled`, and that is load-bearing, not defensive.** `DceRun`
exits at its first line when DCE is off, leaving `DceLive` an unallocated
dynamic array — so every entry reads "not live" and the predicate would come out
TRUE for every program, dropping an arena the program is about to use. The gate
is the difference between a size win and a heap based at a dropped address.

`BssRemap` **refuses loudly** on an offset inside the hole rather than clamping:
a live reference into dropped storage means the predicate was wrong, and
clamping would resolve it to a neighbouring variable — the plausible-wrong-value
failure that is most expensive to chase.

### Measured, esp32c3 `--esp-profile=bare`

| program | before | after | `--no-dce` |
| --- | --- | --- | --- |
| `frozen` (one frozen string const) | 66,812 B | **1,276 B** | 66,812 B |
| `strvar` (one `string[16]`) | 66,832 B | **1,296 B** | 66,832 B |
| `alloc` (`SetLength`) | 66,812 B | **66,812 B** | 66,812 B |
| `empty` / `noalloc` / `reconly` | 640 / 652 / 656 B | unchanged | unchanged |

−65,536 B exactly. `alloc` correctly keeps it. `--no-dce` keeps it everywhere,
which is this routine's positive control.

### The run is the proof, not the size column

A bare program printing through UART MMIO with no `AnsiString` anywhere — so
`builtinheap` links, `HeapMmap` dies, the arena drops — carrying **three scalar
globals and an eight-element array global**, all of them user globals and
therefore ABOVE the arena and shifted by the remap:

    x86-64 oracle : hi111-222-333-0,11,22,33,44,55,66,77,
    esp32c3 qemu  : hi111-222-333-0,11,22,33,44,55,66,77,   bss=1324B
    esp32s3 qemu  : hi111-222-333-0,11,22,33,44,55,66,77,   bss=1324B

Wrong remap arithmetic prints garbage here; it does not fail to build.

**The first version of that program proved nothing and looked like it did.** It
used `PutS(const s: AnsiString)`, which materialises and keeps `HeapMmap` alive,
so it measured 66,848 B, ran perfectly, and never entered the changed path. The
size column is what caught it. A runtime check that does not reach the changed
code passes for the wrong reason.

### Not checked, and bounded rather than cleared

Whether `BssRemap` composes with `RoSplitActive`, and the ESP object-writer
path. `BssDropLen` is 0 for every target and profile except bare ESP with a dead
`HeapMmap`, so the exposure is the case measured above — but bounded is not
checked, and both were named by e5 when it proposed the shape.

### One more thing the loud refusal bought, unplanned

Because `BssRemap` **errors** on an offset inside the hole rather than clamping,
the fact that `frozen`, `strvar` and the qemu witness build at all is
independent evidence that DCE correctly compacted away the dropped `HeapMmap`
body's `GlobFix` entries. A stale fixup pointing into the arena would have
stopped the build with a named diagnostic. The backstop turned out to double as
a check on the pass it depends on.

### Suite

`make test-esp-bare`: **21 ok, 1 fail — identical to the baseline taken before
this change.** The single failure is
`bug-a-a-function-returning-a-record-by-value-fails-to-compile-on-four-targets`
(p85, `523833fde`, filed separately), a compile failure with no connection to
this work. Self-host fixedpoint converged. Hosted targets unaffected:
`BssDropLen` is 0 off the bare-ESP path.

## Why this is the right resource

Owner, 2026-09-20: *"SRAM here is most relevant, ESP's have 'plenty' flash
memory so that's a lesser issue."* Image-size wins are the lesser axis; this one
is SRAM.

## The precedent, four days old

`bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss` was the same
shape at half the size: 32,768 B of BSS reserved whether or not a handler could
exist. `16ebf18ce` fixed it by splitting the reservation into
`EnsureSignalAltStack` and calling it only under the predicate the emitter
already used — *reserved iff emitted*, one place, so a new backend cannot forget.

(Note the sharp edge, paid for on the same
day: a prologue-time READER of a slot whose allocator moved later got silently
nothing — see `12d6c86f0`. Whatever predicate is chosen here must be evaluated
where the arena is *declared*, not where it is first read.)

## Why the blocker ordering was load-bearing (HISTORY -- cleared)

This is retained because it explains the filing order, not because it still
applies: the `PXXDynSetLen` orphan was deleted in `2c59f8326` and `blocked-by`
is empty. At HEAD the predicate does come out false -- `frozen` above drops all
78 allocator bodies -- so the guard this ticket needs is now testable.

While the `PXXDynSetLen` orphan exists it roots `PXXAlloc` unconditionally, so
"is the allocator reachable" **can never answer false**. A guard written against
that predicate today would pass on every program and could not be shown to fail
— a guard that cannot fail. De-duplicate first; the predicate becomes decidable
and testable in the same step.

## Honest bound on the win

**Narrower than the ticket first claimed, and the table above is what narrows
it.** This is not 64 KiB for "programs that do not allocate" -- a program that
does not link the heap unit at all already pays nothing (`noalloc`, 652 B). It
is 64 KiB for programs that **link builtinheap for a non-allocating reason**,
and one frozen string constant is enough to put a program in that set.

I have not measured how large that set is among real ESP programs, and I am not
quoting a fraction of free DRAM here: the 276,832 B pool figure the ticket was
filed with is frankz-e5's, I never re-derived it, and with the witness corrected
the ratio would have to be recomputed anyway. What is measured is the shape:
**524 B of code carrying 65,536 B of arena.**

The argument is still the alt stack's -- a facility the program provably cannot
reach should not be the largest single item in its SRAM -- and it is the second
such item found in five days.

A larger, separate question this does not address: whether `HEAP_ARENA` should
be *sized* per program rather than being one 64 KiB constant. That is design and
belongs under the umbrella, not here.

## Log
- 2026-09-22 - resolved. The FIX and the close are the same commit here - commit 04e20af2c.
