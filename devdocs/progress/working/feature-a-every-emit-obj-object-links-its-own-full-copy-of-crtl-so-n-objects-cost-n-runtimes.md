---
slug: feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes
title: "N objects link N copies of crtl: weak resolves the symbol, it does not drop the bytes"
track: A
prio: 55
type: feature
status: working
created: 2026-09-01
found-by: frankA
owner: frankA
blocked-by: []
summary: "Two --emit-obj objects now link and share one runtime (bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link), but WEAK only picks a winner among duplicate symbols -- the losing objects' sections are still linked in whole. Measured: two objects that each contain crtl produce a 580088-byte binary against 310544 for one, and busybox's 41-TU separate build came out at 13.7MB for the same reason. Needs section-granular deduplication: a crtl archive the linker pulls members from, or function/data sections plus COMDAT groups. STEP 1 IS IN: --function-sections turns internal calls into relocations against the callee symbol (1078 of 1084 sites in a C object; the 6 left are the duplicate-static shape and need a per-BODY symbol), verified by the linked binary being BYTE-IDENTICAL with the flag on and off. It shrinks nothing on its own -- the payoff needs per-function sections + --gc-sections, which is a restructuring of writeELFRelX64General's fixed 9-section layout, and ProcAddrFix relocates against the .text SECTION symbol so it breaks there too. PARKED AFTER STEP 1 (533858cce, --function-sections: internal calls become relocations). MEASURED ON THE PARKED TREE AT 39c7042211a7, two things the next session needs: (a) --function-sections DOES NOT PRODUCE FUNCTION SECTIONS -- the object still has one .text and 13 sections, so -Wl,--gc-sections drops 168 bytes of 624888 (0.03%) in every combination; the flag does what its help text says and its NAME asserts a property step 2 has not built yet. (b) Step (3), DCE under --emit-obj, is now on for BOTH frontends (60edd4853 wired the C one in; passages above saying it is off for C are stale) and its residual is PINNED BY BEING EXPORTED, not unpruned: a C object exports 286 crtl entry points WEAK, --dce drops 269 LOCAL bodies and exactly ZERO weak ones, and those 286 hold 52% of the pruned object's .text. No compile-time pass may contradict an export contract, which is a second independent argument for option (4)'s COMDAT group. Cost of separation for a 3-TU C program: 242568 without --dce, 42176 with it. tools/busybox_diff.sh takes an opt-in --dce so the 149-object number can be retaken; unrun here, no busybox tree on this box."
---

# N objects cost N runtimes

The collision is fixed and the size is not. A weak definition tells the linker
which `malloc` symbol wins; it says nothing about the 162KB of `.text` the
losing objects still contribute, because inclusion is decided per SECTION and
every object has one big `.text`.

## The two shapes, and they are not equivalent

1. **A crtl archive.** `--emit-obj` stops bundling the runtime; crtl ships as
   `libcrtl.a` and the linker pulls only the members a program references.
   This is what a C toolchain does, it makes the duplicate-symbol question
   disappear rather than answering it, and it is the shape frankD proposed as
   option 2. It changes the INTERFACE: a pxx object stops being self-contained,
   so every consumer needs the archive on its link line.
2. **Function/data sections plus COMDAT groups.** The object stays
   self-contained and `--gc-sections` drops what is unreachable. No interface
   change, but it needs per-symbol sections throughout the backend and a group
   section per runtime entry point.

Worth measuring before choosing: how much of the 310544 a trivial program
actually reaches. If it is most of it, (1) is the only one that pays.

## What must not regress

`test-emit-obj` block 4b-septies asserts two objects share one heap, one
`errno` and one `optind` against a gcc oracle. Under (1) that row still has to
pass with the archive on the link line, and the weak binding stops being what
carries it -- so the row's aim checks (weak FUNC count, weak OBJECT count) would
need rewriting rather than deleting, or they become vacuous rather than false.

## The measurement this ticket asked for, taken

frankA, 2026-09-01, compiler `4fa89436ffe7`. The ticket said to measure how much
of an object a trivial program actually reaches before choosing a shape. It is
essentially all of it, and the measurement turned up a structural fact that
changes the cost of both options.

**1. A one-line program carries the whole runtime.** `int plain_add(int,int)`
produces 421 FUNC symbols and 103083 bytes of `.text`, of which the user's
function is 118 bytes at offset 0x191de — **99.8% of `.text` is before it.**

**2. Nothing already prunes it.** `--dce`, `-O2` and `-O2 --dce` all produce
byte-identical output: `code=103083B procs=429` in every case. So there is no
existing switch to measure against, and the 13.7MB busybox number is 41 copies
of this.

**3. The runtime is contiguous — except for a tail emitted AFTER the user's
code.** `__pxx_fegetround` sits at 0x191cc in every object, immediately before
the user's first proc; `__pxx_run_finalizers` sits after it.

**4. Two objects' runtime prefixes differ in exactly TEN bytes out of 102878**,
and all ten are references from the runtime bulk into that trailing tail:

```
0x000b0b in PXXHeapExhausted   0x0090b0 in PXXVariantError   0x0092bd in PXXRangeError
0x008fc6 in PXXDivZero         0x00915f in PXXInvalidCast    0x0093b1 in PXXExitProcess
0x00920e in PXXOverflow        0x009460 in PXXNilRef
```

Every delta is −36, which is exactly the difference between the two programs'
user code (`plain_add` 118 bytes, `other_fn` 82). Confirmed independently:
`__pxx_run_finalizers` is at 0x19276 in one object and 0x19252 in the other,
36 apart.

## What that means for the two options

**Byte-identity is nearly free and is NOT sufficient.** Emitting the trailing
runtime procs before the user's code would make 102878 bytes of every object
identical — a far smaller change than either option above. But dedup still
fails, because the user's calls INTO the runtime are resolved at emit time as
direct rel32, not relocations: an object has only **7 `.text` relocations in
total**. If the linker keeps object A's runtime copy and discards B's, B's user
code still jumps at a displacement computed for B's own discarded copy.

So the load-bearing prerequisite for BOTH options is the same one: **calls from
user code into the runtime must become relocations against symbols.** The
runtime procs already have LOCAL FUNC symbols, so the names exist; what does not
exist is the decision to relocate rather than resolve. That is the same
substitution as
[[bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link]]
made for DATA references, one layer over.

Rank the work that way: the relocation change is the ticket, and archive vs
COMDAT is a choice made afterwards and cheaply. The ten shifting bytes are worth
fixing in the same pass — they are the tell that emission order splits the
runtime, and a "byte-identical" claim measured before that reorder would be
false by ten bytes with no symptom.

## 2026-09-02 (frankC) — the measurement this ticket asked for, and it does NOT say what the tie-breaker expected

Reproduced first, at `18b3ec2a6`, x86-64, three C translation units where only
`main` does anything (`printf("%d")`) and the others define one function each:

| link line | size | delta |
| --- | --- | --- |
| 1 object | 369040 | — |
| 2 objects | 488304 | +119264 |
| 3 objects | 611648 | +123344 |
| same program, no `--emit-obj` (pxx links it) | 307280 | — |

So ~120KB per extra object, confirmed, and a single object already carries
135208 bytes for a one-line function.

**How much does a trivial program reach? 16.3%, not "most of it".** Walked the
linked binary's call graph from `main`/`_start` over `objdump -d`: 786 FUNC
symbols, 290262 bytes, **47237 reachable (16.3%)**. The walk follows direct
calls only, so two things were checked before trusting it: `.data` holds
**2** function pointers in the whole object (not a dispatch table that would
make everything reachable), and the binary has **23** indirect call/jmp sites
total. Positive control, drawn from this same binary: `printf` is in the
reachable set, `qsort` and `strtod` are not.

**A second source that fails differently agrees.** The compiler's own DCE report
on the Pascal side — a call-graph table built during compilation, not a
post-hoc disassembly — says of a `WriteLn('hello')` program:

```
dce: bodies 128  live 45 (16044B)  dead 82 (47579B)  dropping 82 (47579B)
dce: code 64975B -> 17396B
```

**73% dead**, against the disassembly walk's 84% unreachable on the C side. Two
instruments that can go wrong in unrelated ways, one answer.

### The finding that changes the arithmetic: DCE IS SWITCHED OFF FOR EXACTLY THIS CASE

`dce.inc:227` — `if EmitObjMode or EmitSharedMode then why := '-c / --shared
carry their own code-offset relocations'`. So an `--emit-obj` object keeps
every body, and the duplication this ticket is about is duplication of a
runtime that was **never pruned once**. (It is also off for every non-x86-64
target, with `-g`, and for every frontend but Pascal — so the C objects
measured above could not have been pruned on two counts.)

That reframes both options rather than choosing between them:

- The archive (1) fixes only the CROSS-object half. Each member still arrives
  whole, and the ~75% within it is untouched.
- Function sections + `--gc-sections` (2) fixes BOTH halves with one mechanism,
  because the linker's reachability is the same reachability DCE computes —
  and it needs no interface change.
- There is a **third, much smaller** step neither option lists: make DCE run
  under `--emit-obj` by rooting it at the exported symbols. It does not
  deduplicate across objects at all, but it would cut each object's runtime
  contribution from ~135KB to ~20KB, which turns N×135KB into N×20KB and buys
  time to do (2) properly.

**Recommendation: (2), and (3) first if (2) is not going to be picked up
soon.** Not started here — it is a backend-wide change and this session could
not have verified it in the sitting it had. The measurement is banked, which is
what the ticket asked for.

## 2026-09-02 (frankC) — step (3) LANDED for Pascal objects: DCE now runs under `--emit-obj`

The step this ticket's own recommendation called "third, much smaller" is in.
`--dce --emit-obj` was a documented no-op; it is now the difference between
these two columns, measured on `test/test_emit_obj.pas`, x86-64:

| | base | `--dce` |
| --- | --- | --- |
| object | 133608 | **31312** |
| `.text` | 109400 | 18791 |
| FUNC symbols | 223 | 54 |
| 2-object link | 156496 | **57080** |
| 3-object link | 227936 | 77376 |
| **marginal cost of one more object** | 71440 | **20296** |

Every link answers identically (`done99 pxx-emit-obj`, `42 42 42`), the export
surface is byte-for-byte the same symbol list, and `AddUp` — a LOCAL reachable
only from an export — survives while `FloatToStr` goes.

So N×135KB became N×20KB, which is what step (3) promised. It does **not**
deduplicate across objects: options (1) and (2) above are untouched and still
the answer to the ticket's title.

### The refusal was right in the aggregate and wrong about almost all of itself

`-c / --shared carry their own code-offset relocations`. They do. But every
table those relocations are built from — `Fixups`, `GlobFix`, `CallFix`,
`ProcAddrFix`, `DynCall`, `CodeRef`, `Procs[].BodyAddr` — is one the pass
already compacts and re-patches, because an ET_EXEC image reads the same
tables. **Exactly two code offsets were outside them**, and they are not in any
fixup table at all: `InitThunkOff` and `FiniThunkOff`, stated raw as
`.text + <offset>` in `.rela.init_array` / `.rela.fini_array`.

Lifting the refusal without them produced a **4.3x smaller object that
SIGSEGVs before `main`** — the size row alone would have called that a success.
Three things were needed:

1. **A root set.** An executable is rooted at its entry point; an object's
   callers are outside it. Rooting at `ObjProcIsExported` — the object writer's
   own predicate, asked rather than restated, so the root set and the GLOBAL
   symbol block cannot drift — is what makes the pass useful rather than
   merely correct. Without it the pass deletes the object's whole reason to
   exist. (This is also why `dce.inc` now includes *after* `elfwriter.inc`.)
2. **The thunks kept alive.** They are not a clean tail: measured here, the
   init thunk is at `0x1aae4` and `__pxx_run_finalizers`' body at `0x1ab28`, so
   both thunks fall INSIDE the removable range of whatever proc precedes them,
   which is a different proc in every program. Registered as stub targets — the
   existing mechanism — and remapped through `DceNewOff`.
3. **One hand-written rel32 recorded.** The init thunk's `call <code offset 0>`
   is computed against a fixed target rather than routed through `CallFix`,
   because its callee is the program body and no `Procs[]` row names it. It now
   goes through `RecordCodeRef`. That single unrecorded displacement was the
   segfault.

`--shared` still refuses, with an accurate reason instead of the old one: its
exported surface goes through a `.dynsym` and a GOT this pass has never been
read against, and turning both on from one measurement would leave the failing
one unidentified.

### Still off, and each is a separate question

`--emit-obj` from the **C frontend** (`not IsPascalFrontend`), every non-x86-64
target, and `-g`. The busybox 13.7MB number is C, so this does not move it —
wiring the C frontend into DCE is the next step for that consumer and is not
this change.

## 2026-09-02 (frankC) — the C half, and it is NOT this ticket's title

DCE now runs for the C frontend too (`60edd4853`), so `--emit-obj --dce` is
available to the consumer this ticket was really about. **It barely helps, and
the reason is a different bug.**

One C translation unit, two exported functions plus a `static` helper, using
`snprintf`/`malloc`/`strlen`:

| | bodies live | bytes |
| --- | --- | --- |
| `--emit-obj --dce` | **529 of 804** | 291416 |
| the SAME code as an executable, `-O3` | **78 of 805** | 78488 |

Same source, same pass, same reachability algorithm. The object keeps **6.8x
more code** than the executable, and the difference is entirely the ROOT SET.

### Every crtl function is an export root, and the predicate cannot tell

`ObjProcIsExported` is `ProcCdecl and not ProcCStaticLink`. **Every crtl routine
satisfies it** — `malloc`, `qsort`, `strtod`, the float formatting, all of it —
because crtl is C and C functions are cdecl and non-static. So a one-line
translation unit roots 288 exported FUNC symbols, of which two are the user's.

The predicate is not wrong about export policy; it is being asked a question it
was never designed for. "What must this object make link-visible" and "what
must survive so this object works" were the same set until a pass started
deleting things.

### What that means for the three options above

The **third step (per-object DCE) is landed and blocked, not spent.** It cuts a
PASCAL object 4.3x (`6a084d569`) because a Pascal object exports only its
explicit `cdecl` routines and the RTL is on the internal convention. A C object
exports its whole runtime and so keeps it.

The prerequisite for the C consumer is therefore **not** the relocation change
this ticket identified for options (1) and (2). It is smaller and prior to all
three: **distinguish this translation unit's own functions from the crtl pulled
in behind them.** The C frontend already knows — `ParseCProgram` holds
`crtlStart`, the token index the crtl pull begins at, and uses it to bound two
loops. Nothing carries that distinction onto the `Procs[]` row.

Rough arithmetic on the busybox number, on these measurements: 41 TUs at ~78KB
of reachable code rather than ~335KB is single-digit MB rather than 13.7MB —
before any cross-object dedup at all.

### The interface question that has to be answered first, and it is real

Dropping unreached crtl from an object CHANGES ITS LINK SURFACE: the symbol
goes, not just the bytes. Today an object exports its whole runtime weakly, and
`test-emit-obj` block 4b-septies asserts two objects share one heap, one `errno`
and one `optind` against a gcc oracle. That row should survive — it pins DATA
symbols, and code DCE does not touch `.bss` — but "should" is not "measured",
and the honest reading is that this moves an object toward option (1)'s
semantics (a pxx object stops being a self-contained runtime) without the
archive that makes that deliberate. Worth deciding rather than assuming:
whether a pxx object is a self-contained runtime or a translation unit.

## 2026-09-02 (frankC) — the "7 relocations" number is WRONG, and the prerequisite it states is right

Re-measured at `67bf0612e`, x86-64, before starting the relocation work this
ticket ranks first. **The claim above — "an object has only 7 `.text`
relocations in total" — does not reproduce.**

| object | `.rela.text` | `.rela.data` | `.rela.init_array` | `.rela.fini_array` |
| --- | --- | --- | --- | --- |
| C, one function + `main` | **1699** | 5 | 1 | 1 |
| Pascal, one `cdecl` function | **191** | 63 | 1 | 1 |

The first count I took said 1706 and was also wrong: the awk set a flag at
`.rela.text` and never cleared it, so it counted every later RELA section too.
An instrument that answers about the wrong population does not error — it
answers. The table above is from a per-section parse, cross-checked against
`readelf -S` sizes.

**The SUBSTANCE of the claim survives and is sharper than the number was.**
Classifying every `.rela.text` entry by what it TARGETS:

```
a.o (C):      1072 -> .bss    423 -> .data    114 -> errno   48 -> optind   8 -> opterr
p.o (Pascal):  136 -> .bss     55 -> .data
              ---- FUNC-targeting entries, both objects: ZERO ----
```

Every one is a DATA reference. So the real prerequisite is not "an object has
almost no relocations" (it has 1699) but the exact statement:

> **No relocation in `.text` targets a FUNC symbol. Every internal call is a
> displacement baked at emit time by `ApplyCallFixups`.**

That is a one-line check anyone can re-run, it cannot be confused with the
data relocations that already exist in quantity, and it is what the reorder /
dedup work actually has to change. `ApplyCallFixups` (symtab.inc) patches every
`CallFix` site for every architecture; nothing in the x86-64 object path turns
one into a relocation. The machinery to do so already exists and is used on
another target: `ObjProcSymIdx[]` plus `writeRela64`, which is how the xtensa
IRAM path (`IramCallFix`) relocates its calls.

Also worth correcting for whoever picks this up: `ProcAddrFix` (`@proc`) DOES
relocate, but against **section symbol `.text` + addend**, not against the
proc's own symbol — so it is section-relative and would break under
per-function sections exactly like a baked call does. It needs the same
substitution.

## `--gc-sections` SIDESTEPS THE INTERFACE FORK — option (2) is not blocked

The open question in `decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit`
blocks narrowing the DCE ROOT SET, because dropping an unreached crtl routine
from an object removes its SYMBOL and changes the link surface that
`test-emit-obj` 4b-septies pins.

Option (2) does not have that problem, and this is the reason to prefer it
rather than wait for the ruling. At a FINAL link `--gc-sections` computes
reachability from the ENTRY POINT; a global symbol is not a root there (that is
shared-library behaviour). So per-function sections let the linker drop the
BYTES of unreached crtl while the object still EXPORTS every symbol it exports
today. The link surface is unchanged, 4b-septies keeps its meaning, and the
fork stays open without blocking the work.

That makes the ranking: relocations first (this ticket's own recommendation),
then per-function sections, both behind a flag so `--emit-obj` cannot regress
for the busybox consumer while they land incrementally.

## 2026-09-02 (frankC) — the relocation step is IN, behind `--function-sections`

This ticket's own ranking: *"the relocation change is the ticket, and archive vs
COMDAT is a choice made afterwards and cheaply."* That change is landed, opt-in.

`--function-sections` under `--emit-obj` turns an internal call into an
`R_X86_64_PC32` against the callee's own FUNC symbol instead of the displacement
`ApplyCallFixups` bakes.

| | CallFix sites | relocated | still baked |
| --- | --- | --- | --- |
| C object (`printf` + a 3-deep chain) | 1084 | **1078** | 6 |
| Pascal object | 253 | **253** | 0 |

### It has NO observable effect, and that is how it is verified

With one `.text` section the linker must compute exactly the displacement that
was baked, so **the linked binary is BYTE-IDENTICAL with the flag on and off** —
asserted for both frontends, alongside a control proving the two OBJECTS really
differ. A step that changes nothing can only be verified by proving it changed
nothing, and only a control separates that from a flag that never ran.

### Two instrument failures on the way, both worth keeping

**1. The predicate looked obviously right and was wrong about 93% of the sites.**
It refused any site with `CallFixTarget >= 0`, reading that as "pinned to a
specific body — the C duplicate-static case". But `CallFixTarget` is an
*unconditional snapshot* of `Procs[procIdx].BodyAddr` taken when the site is
recorded (symtab.inc), so it is `-1` only for a FORWARD reference: the test
refused every BACKWARD call. **1004 of 1084 rejected, 80 accepted.** The real
hazard is narrower — the snapshot DISAGREEING with the row, which is the actual
duplicate-static case and is 6 sites, not 1004.

What caught it was printing the breakdown rather than reasoning about it. The
first reading was "80 relocations against 1124 call instructions", and no amount
of thinking about `EmitCallProc` would have said which of four reasons owned the
other 1044. `ObjReportFunctionSections` is kept for that reason: the number that
matters is how many sites remain BAKED, because per-function sections cannot
land while any do.

**2. Two linked binaries differed by 10755 bytes and 100% of it was the
filename.** `gcc` records the input object's name as an `STT_FILE` symbol, so
`off.o` vs `on.o` shrank `.strtab` by the one character of the name and shifted
every offset after it. `.text`, `.data` and `.rodata` were byte-identical the
whole time. The fix is one object path, each linked before the next compile
overwrites it — the same shape a C sweep in this session needed for the same
reason, and it is now written into the Makefile rows as a comment rather than
left to be rediscovered.

### What this does NOT do

It does not shrink anything. Object grows slightly (1699 -> 1779 `.rela.text`
entries on the C file). The payoff needs per-function sections plus
`--gc-sections`, and **that is a restructuring of `writeELFRelX64General`, which
is built around a FIXED 9-section layout with hard-coded offsets and a 66-byte
`.shstrtab` blob** — N sections means N section headers, per-proc `st_shndx`,
section-relative `r_offset` and a `.rela.text.<name>` each. That is the
backend-wide job frankA flagged and it is deliberately not in this flag.

Two things the next session needs, both measured here rather than assumed:

- **`ProcAddrFix` (`@proc`) relocates against the `.text` SECTION symbol plus an
  addend**, so it is section-relative and breaks under per-function sections
  exactly like a baked call. It needs the same substitution and is not covered
  by `--function-sections` today.
- **The 6 baked sites are real and must be handled, not waved at.** They are the
  duplicate-static shape (`test/cstatic_same_module_dup.c`); relocating them
  against the proc symbol re-aims them at the wrong body, which links cleanly and
  runs the wrong function. Per-function sections needs a per-BODY symbol there.

`test/c_function_sections.c`, wired as `test-emit-obj` block 4a-bis. Whole
`test-emit-obj` target green with the flag default-off, so the existing path is
untouched.

## 2026-09-02 (frankC) — option (4): ONE COMDAT group, not 1650 sections. Much cheaper than (2), and step 1 just unblocked it

Measured at `533858cce` on `test/c_function_sections.c` (805 FUNC symbols), and
it reconfirms frankA's contiguity finding on a different program:

```
rank   1..800  the runtime, ending at pclose            0x00000..0x48641
rank 801..804  deep3, deep2, deep1, main  (USER CODE)   0x488c8..0x489fe
rank     805   __pxx_run_finalizers        (THE TAIL)   0x4c4e0
```

**The user's code is ranks 801-804 of 805.** The runtime is a single contiguous
PREFIX with exactly one function stranded after the user's code. So the
crtl/user boundary is ONE SPLIT POINT, not a per-function property.

That admits a shape the three options above do not list:

> **(4) Emit the runtime as one contiguous prefix in its own COMDAT group.**
> Move the trailing tail (`__pxx_run_finalizers`, and the init/fini thunks)
> ahead of the user's code, put the runtime prefix in a group section with a
> fixed signature, and leave the user's code in plain `.text`. The linker keeps
> ONE copy of the group across N objects and discards the rest.

### Why this is the cheap one

- **Two text sections, not ~1650.** `writeELFRelX64General` is hand-unrolled
  around a FIXED 9-section layout with hard-coded `.shstrtab` name offsets
  (1, 7, 18, 24, 35, 40, 48, 56) and a literal `numSects := 9`. Adding a
  bounded number of sections is the shape it already supports — that is exactly
  how `.init_array`/`.rela.init_array` were added, conditionally, with the
  offsets recomputed. Adding N-per-proc is a rewrite of that writer.
- **It attacks this ticket's TITLE directly.** N×135KB becomes 1×135KB plus
  N×(user code). Per-function `--gc-sections` would additionally drop the ~84%
  of the runtime nothing reaches, but that is a SECOND win and the title is the
  first one.
- **Step 1 is its prerequisite and is landed.** COMDAT means the losing copies'
  code is DISCARDED, so callers in those objects must be re-aimed at the kept
  copy. That is only possible because internal calls are now relocations
  (`533858cce`). This is the same prerequisite option (2) needed; it is spent
  either way.
- **The ten shifting bytes stop being a problem, and stop being a puzzle.**
  frankA measured that two objects' runtime prefixes differ in exactly TEN bytes
  of 102878, every one a reference from the runtime bulk INTO the trailing tail,
  each delta equal to the difference in the two programs' user-code sizes.
  Moving the tail ahead of the user's code removes the only thing that made the
  prefixes differ — and byte-identical prefixes is precisely the property COMDAT
  wants, since the linker keeps one copy and assumes the others were the same.

### What still has to be answered before building it

- **Does the group's signature symbol collide?** All N objects must name the
  same signature for the linker to dedup them, and that symbol has to be
  reachable in `.symtab` without becoming part of the export surface.
- **`.data`/`.bss` are NOT covered by this.** The group would hold `.text` only;
  the runtime's data still lands per-object, and `test-emit-obj` 4b-septies pins
  exactly that (two objects sharing one heap, one `errno`, one `optind`). Weak
  binding still carries those, so the row keeps its meaning — but that is
  reasoning, not a measurement, and it should be measured before landing.
- **`ProcAddrFix` relocates against the `.text` SECTION symbol plus an addend.**
  With the runtime in a different section from the user's code, a `@proc` naming
  a runtime routine points at the wrong section. It needs the same substitution
  the calls just got, and this is true for option (2) as well.

**Recommendation, revised: (4) then (2).** (4) is a bounded change to the writer
that fixes the title; (2) remains the bigger win and the bigger job, and neither
is blocked by
[[decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit]],
because both drop BYTES while leaving the export surface alone.

Parked here rather than started: the emission reorder alone changes where every
proc lands, and landing that half-verified would destabilise `--emit-obj` for
the busybox consumer and for Track T.

## Parked 2026-09-02

step 1 (--function-sections, internal calls become relocations) landed at 533858cce. Parked before step 2: the remaining work is an emission reorder plus COMDAT group sections (option 4, measured and written up in the ticket), which changes where every proc lands and would destabilise --emit-obj for busybox and Track T if landed half-verified.

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

## 2026-09-02 (frankA) — measured on the parked tree: `--gc-sections` drops 0.03%, and the reason is the export surface

Two measurements taken after step 1 landed, at `bc8fa306b`, compiler
`39c7042211a7`. Neither changes the park; both change what the next session
should expect from step 2, and one of them is a name-is-not-the-thing trap
sitting in the tree right now.

### `--function-sections` does not produce function sections

The flag does exactly what its help text says — *"relocate internal calls
against the callee's symbol"* — and that is step 1 and it works: `CallFix 497
relocated 497 pinned-target 0 undefined 0 no-symbol 0`. But the object it emits
still has **one `.text`**, 13 sections in total, no `.text.*` at all. So the
name asserts a property the artifact does not have, and the obvious next thing
anyone tries measures as nothing:

| per-TU flags | plain link | `-Wl,--gc-sections` |
| --- | --- | --- |
| none | 624856 | 624680 |
| `--dce` | 336016 | 335848 |
| `--function-sections` | 624888 | 624720 |
| `--function-sections --dce` | 336064 | 335896 |

**168 bytes, 0.03%, in every row.** `--gc-sections` has nothing to collect
because section granularity has not changed yet. That is not a defect in step 1
— it is step 2 not being built — but the flag name will be read as the mechanism
being in place, by exactly the person who reaches for `--gc-sections` next.
Worth renaming when step 2 lands and the name becomes true, not before; worth
knowing about now. All eight binaries print `8`.

### Why option (4)'s COMDAT is the one that can work, measured rather than argued

Step (3), DCE under `--emit-obj`, is now on for both frontends (`60edd4853`
wired the C one in; the section above this still says it is off, which is
stale). It prunes a C object far less than a Pascal one, and the ratio names the
mechanism. One C source, one compiler, three builds differing only in root set:

| build | root set | live bodies | `.text` |
| --- | --- | --- | --- |
| executable, `--dce` | the entry point | 73 | 62181 |
| `--emit-obj --dce` | entry **+ 286 weak crtl exports** | 528 | 236656 |
| `--emit-obj`, no dce | — | 803 | 312412 |

**The export surface costs 174475 bytes per object — 2.8x the whole reachable
program — and it is the same 174KB in every object.** The pass drops 269 LOCAL
bodies and **exactly zero WEAK ones**:

```
                     GLOBAL      WEAK           LOCAL
  C object, base       2/7693B   286/121946B    515/173823B
  C object, --dce      2/7693B   286/121946B    246/98067B     <- WEAK unchanged
  Pascal object        3         0              241            <- no weak surface
```

52% of the pruned C object's `.text` sits in those 286 WEAK symbols, and most of
the surviving LOCAL bytes are reachable *from* them. Pascal prunes 78% and C
prunes 24% for one reason: the Pascal object exports three symbols and the C
object exports the runtime.

**This is `243137302` being paid for.** Exporting crtl WEAK is what made two
objects link and share one `errno`. It is also a contract saying "any of these
286 may be called from outside this object", and no compile-time pass may
contradict it. So the ~21KB per object that `--dce` leaves behind is not
unpruned code — it is **pinned, correctly**, and the only thing that can reach
it is a mechanism that runs where the weak winner is known. That is option (4)'s
COMDAT group, and it is a second, independent argument for the recommendation
already recorded above.

Cost of separation today, 3-TU C program, gcc linking:

| | unity (1 object) | 3 objects | cost of separation |
| --- | --- | --- | --- |
| no `--dce` | 382288 | 624856 | **242568** |
| `--dce` | 293840 | 336016 | **42176** |

~121KB per extra object down to ~21KB, and a leaf object 135232 -> 23496.

### `tools/busybox_diff.sh --dce`, opt-in

The harness compiles each TU with a bare `--emit-obj`, so none of the above
reaches the 149-object build the 13.7MB number came from. It now takes `--dce`
(separate mode only, default off), and the note line prints the per-TU flags
beside the byte count, because the number this ticket is ranked on moves by a
factor with them.

**Not run here: there is no busybox tree on this box** and fetching one is a
network act. The switch is for whoever holds the tree, and the correctness
question it answers — does `--dce` survive 149 real translation units — is worth
more than the size.
