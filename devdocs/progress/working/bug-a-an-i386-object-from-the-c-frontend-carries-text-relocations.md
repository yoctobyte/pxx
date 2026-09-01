---
slug: bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations
track: A
prio: 40
type: feature
status: working
blocked-by: []
owner: frankC
created: 2026-09-01
found-by: frankA (while adding .init_array to the i386 object writer; pre-existing, not caused by it)
summary: "i386 --emit-obj output is POSITION-DEPENDENT: .text relocations are absolute R_386_32, so `-Wl,-z,text` refuses the link and a PIE gets DT_TEXTREL. The i386 twin of feature-a-x86-64-object-output-is-position-dependent, and the harder one: i386 has no [eip+disp32] ADDRESSING MODE, so it needs an explicit call/pop anchor where x86-64 has rip -- but it does NOT need a GOT: our .data/.bss symbols are section-local, so a PC-relative anchor reaches them with a link-time-constant displacement (measured: assembles to R_386_PC32, links under `gcc -m32 -pie -Wl,-z,text`, runs, no GOT and no R_386_GOTPC). LANDED SO FAR: the per-body anchor (e1209443d), R_386_PC32 writer support (6ab85feb8), and the FIRST conversion family -- absolute [disp32] LOADS from a global, 8B/8A/0F B6/0F B7/0F BE/0F BF with mod=00 rm=101, rewritten to `mov dest,[ebp+picslot]` plus the same instruction rebased on dest (b64341130). 114 of 502 .text relocations in test_emit_obj now convert; 388 remain. THE BASE-REGISTER QUESTION IS CLOSED AND THE ANSWER IS NEITHER esi NOR ebx: the anchor is parked in a FRAME SLOT and each reference loads it into a register that is provably free AT THAT SITE -- its own destination for a load, a push/pop-wrapped scratch for a store -- so no sequence preserves anything across it and the 12-site esi liveness audit an earlier revision planned is not needed at all. REMAINING FAMILIES, from the emitter census (PXXDBG=a.i386reloc, 11645 sites, and it found three shapes no object census held): stores (89/88/C7), cmp (39), moffs (a1/a2/a3), address-as-immediate (b8..bf), push imm32, SIB-indexed, and `c7 00` mov [reg],imm32 with the data address as the IMMEDIATE (74 sites, the one shape needing a scratch the emitter must find). MEASURED GATE FINDING, and the reason a new subject exists: test-emit-obj rows 4b/4d and test-c-abi-mixed-link ALL PASS against a compiler whose PC-relative addend is deliberately wrong by 0x30000000 -- they emit converted sites and never EXECUTE one. test/i386_pcrel_globals.c segfaults against that compiler and is therefore the only aimed guard here."
---

# An i386 object from the C frontend carries text relocations

Found while making i386 objects run their initialisers
(`bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers`). **Not caused
by that work** — measured on an object built before it and one built after, and
both produce the same two warnings:

```
ld.bfd: cl386.o: warning: relocation in read-only section `.text'
ld.bfd: warning: creating DT_TEXTREL in a PIE
```

## Why it matters despite the program running

`ld` resolves this by marking `.text` writable at load. So the object links, the
program runs, every existing row stays green — which is exactly why it survived.
What it costs is real: `-Wl,-z,text` refuses the link outright, hardened
distributions build with it, and a writable `.text` cannot be shared between
processes.

## The x86-64 side already solved this and the difference is instructive

`test-emit-obj`'s x86-64 rows assert that `.text` carries **no** absolute
relocation, and that assertion exists because `IR_PROCADDR` was emitting
`mov rax, imm64` — an `R_X86_64_64` against `.text` — until the `@proc` case was
added to `test/test_emit_obj.pas` specifically to give the census a population
that could contain it. The comment there says so.

**i386 has no equivalent row.** So the same class of defect is unmeasured on a
target that has an object writer, which makes this a test gap first and a codegen
bug second. Adding the assertion is the cheap half and should probably come
first; it will name the sites.

## Re-scoped 2026-09-01 after censusing it

I filed this as "convert the offending sites". It is not that.

    .rel.text, Pascal i386 object   518 R_386_32, nothing else
    .rel.text, C i386 object        566 R_386_32, nothing else

Every relocation in `.text` is absolute. So the work is the i386 twin of
`feature-a-x86-64-object-output-is-position-dependent` — a backend model change,
which that ticket did in three phases.

**And i386 is the harder of the two.** x86-64 had `rip`-relative addressing to
convert to, so the fix was largely a different encoding for the same operand.
i386 has no PC-relative data addressing at all: position independence means
establishing a GOT base in a register (conventionally `ebx`, via the
`call/pop` thunk idiom) and addressing through it, which touches the register
allocator and the prologue rather than just the operand emitter.

**Do NOT just add the assertion to go red.** The obvious first step — mirror the
x86-64 row that asserts `.text` carries no absolute relocation — would turn
`test-emit-obj` red on a target that has never been green on this property, and
that costs Track T's signal for everyone while buying information this census
already gives. The row lands with the fix, not before it.

**A trap for whoever writes that row:** this file's own `.rel.init_array` entry
is an `R_386_32` against the `.text` SYMBOL and is not an instance of the bug —
it patches a slot in `.init_array`. The x86-64 row gets this right by scoping
with `sed -n '/rela.text/,/^$/p'` before grepping, i.e. by relocation SECTION
rather than by symbol name. Copy that shape.

Note for whoever takes it: the `.rel.init_array` entry added on 2026-09-01 is an
`R_386_32` against the `.text` symbol and is NOT an instance of this bug — it
patches a slot in `.init_array`. An assertion written as "no R_386_32 mentioning
.text anywhere" would flag it and be wrong.

## THE CENSUS THE TICKET ASKED FOR (2026-09-01, frankC)

Three objects — a C one, a Pascal one, and a Pascal `--threadsafe` one — every
`.text` relocation matched back to the instruction that contains it, **1482
sites, 24 distinct operand shapes, 0 unmatched.** Every one is `R_386_32`, and
every one targets `.data`, `.bss` or `.text`; there are **no external symbol
references in `.text` at all**, and intra-object calls already need no
relocation. So this is entirely about addressing our own data.

| N | prefix | trail | example | rewrite | Δlen |
| ---: | --- | ---: | --- | --- | ---: |
| 301 | `a1` | | `mov eax,ds:d32` | `8b 83` + d32 | **+1** |
| 180 | `88 1d` | | `mov [d32],bl` | ModRM → `9b` | 0 |
| 180 | `8a 1d` | | `mov bl,[d32]` | ModRM → `9b` | 0 |
| 160 | `b9` | | `mov ecx,imm32` | `8d 8b` + d32 (`lea`) | **+1** |
| 156 | `8b 15` | | `mov edx,[d32]` | ModRM → `93` | 0 |
| 119 | `a3` | | `mov [d32],eax` | `89 83` + d32 | **+1** |
| 100 | `68` | | `push imm32` | `53` + `81 04 24` + d32 | **+3** |
| 92 | `b8` | | `mov eax,imm32` | `8d 83` + d32 (`lea`) | **+1** |
| 74 | `bf` | | `mov edi,imm32` | `8d bb` + d32 (`lea`) | **+1** |
| 57 | `89 15` | | `mov [d32],edx` | ModRM → `93` | 0 |
| 24 | `c7 05` | **+4** | `mov [d32],imm32` | ModRM → `83` | 0 |
| 10 | `ff 14 25` | | `call [d32]` | `ff 93` + d32 | **−1** |
| 4 | `89 0d` | | `mov [d32],ecx` | ModRM → `8b` | 0 |
| 4 | `8b 05` | | `mov eax,[d32]` | ModRM → `83` | 0 |
| 3 | `8b 04 d5` | | `mov eax,[edx*8+d32]` | mod→10, SIB base→`ebx` | 0 |
| 3 | `89 04 d5` | | `mov [edx*8+d32],eax` | mod→10, SIB base→`ebx` | 0 |
| 3 | `bb` | | `mov ebx,imm32` | `8d 9b` + d32 (`lea`) | **+1** |
| 3 | `0f b6 05` | | `movzx eax,BYTE [d32]` | ModRM → `83` | 0 |
| 3 | `ba` | | `mov edx,imm32` | `8d 93` + d32 (`lea`) | **+1** |
| 2 | `89 25` | | `mov [d32],esp` | ModRM → `a3` | 0 |
| 1 | `39 35` | | `cmp [d32],esi` | ModRM → `b3` | 0 |
| 1 | `f0 0f b1 0d` | | `lock cmpxchg [d32],ecx` | ModRM → `8b` | 0 |
| 1 | `ff 05` | | `inc [d32]` | ModRM → `83` | 0 |
| 1 | `ff 0d` | | `dec [d32]` | ModRM → `8b` | 0 |

**Every rewrite above was assembled and disassembled, not reasoned about.**

### The ModRM family is ONE expression, and that is the whole of half the work

Twelve of the 24 shapes are a memory operand with `mod=00, rm=101` (absolute
`[disp32]`), and turning it into `[ebx+disp32]` is `mod=10, rm=011` — the
**reg field is untouched**, so:

```
modrm := (modrm and $38) or $83     <-- WRONG REGISTER. $83 is ebx, written
                                        before the base register was decided;
                                        it came out esi, so the constant is
                                        $86. See CORRECTION 1 near the end.
                                        The expression SHAPE is right.
```

covers all of them, **including the `F0`-prefixed `lock cmpxchg` and the
two-byte-opcode `0f b6`**, because only the ModRM byte participates. It is
length-preserving, so no branch offset moves. That is 606 of 1482 sites in one
line, and it is the same trick `EmitGlobRef` already plays for x86-64 — done at
the emitter, where the bytes to rewrite are the last ones in the buffer, rather
than at ~200 call sites.

### THE FOUR SHAPES THAT ONLY A `--threadsafe` BUILD CONTAINS

`39 35`, `f0 0f b1 0d`, `ff 05`, `ff 0d` appear in **one of the three objects**.
`EmitGlobRef`'s own comment records the x86-64 version of this: that census was
sound, gcc-validated, and *empty*, because every object was built without
`--threadsafe` and the shape it was counting lives almost entirely in lock code.
The cost then was a release writing four bytes past the lock word, every worker
spinning forever, and `test_mutex` passing.

**So this census is only valid because the population was widened on purpose,
and the next person to re-take it must widen it the same way.** A census over
the C object alone would have reported 19 shapes and been just as clean.

### What is NOT solved by any of the above

**Establishing the GOT base.** All 1482 rewrites assume `ebx` holds
`_GLOBAL_OFFSET_TABLE_`, and today it does not: the backend uses `ebx` as
short-lived scratch (34 sites inside `IREmitNode386`, 93 in the file), the
`int 0x80` helpers need it as syscall argument 1, and **the census itself
contains `mov ebx, <global>`**. Reserving it means the prologue thunk, the
callee-saved save/restore, and moving those scratch uses — and the syscall
helpers are the awkward ones because `ebx` is architecturally required there.

That is the phase-2 decision, and it is a real one: reserve `ebx` (conventional,
what gcc does, collides with the syscall helpers) versus `esi`/`edi` (no
architectural conflict, unconventional, collides with the string-op sequences).
**Neither is free, and the census does not decide it** — it only proves the
addressing half is mechanical once a base register exists.

`push imm32` (100 sites) is worth noting as the one shape needing no scratch
register at all: `push ebx; add dword [esp], d32@GOTOFF` is +3 bytes and
clobbers nothing, which is better than `lea` into a register the emitter cannot
know is free.

## THE BASE REGISTER IS `esi`, AND IT WAS DECIDED BY MEASUREMENT (2026-09-01, frankC)

The section above left "reserve `ebx` versus `esi`/`edi`" open and said the
census did not decide it. Three measurements do, and none of them needed a
Track U ticket.

**1. `ebx` is conventional for exactly one reason, and that reason is absent
here.** gcc reserves `%ebx` on i386 because the PLT's entry stubs are written
to expect the GOT base there. We have no PLT:

```
R_386_PLT32 in c386.o, p386.o, p386ts.o:  0, 0, 0
```

Every external call is `ff 14 25 <d32>` — `call [d32]` through **our own GOT
slot in `.data`**, which the ELF writer's comment already states outright. So
the convention buys interoperability with a mechanism this backend does not
use, and costs the collision below.

**2. `esi` is the least-used register in generated code, by a factor of 2.8.**
Counted over the `--threadsafe` Pascal object's `.text`:

| eax | ebp | edx | esp | ecx | ebx | edi | **esi** |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 23036 | 10987 | 8928 | 8062 | 4759 | 3595 | 1521 | **1292** |

**3. And this is the one that actually decides it: `esi` CANNOT BE WANTED for
the largest class of sites.** i386 has no REX, so the byte-addressable
registers are exactly `al/cl/dl/bl` (+ `ah/ch/dh/bh`) — `sil` and `dil` do not
exist. 360 of the 1482 census sites are `88 1d` / `8a 1d`, byte moves through
`bl`. Reserving `ebx` would mean relocating every one of them into `al`, `cl`
or `dl` — the accumulator, the shift/second operand, and the 64-bit high half,
all three of which are busier than `ebx` was. Reserving `esi` cannot ever
create that pressure, **because no byte move can name `esi` in the first
place.**

That is the difference between "least used today" and "structurally cannot be
wanted", and only the second one survives the backend growing. Points 1 and 2
are reasons; point 3 is the argument.

### What reserving `esi` still costs, stated plainly

91 `esi` mentions in `ir_codegen386.inc`, all of the same short-lived shape as
`ebx`'s (`mov esi, eax`, use, done — never live across an IR node). They are
the string-compare and string-copy sequences, and each needs re-homing onto
`edi` or a spill. **That is real work and it is not zero**; the claim here is
only that it is the smallest of the three options and the only one that cannot
regrow.

### Phase order, and it is deliberately not the obvious one

1. **Reserve `esi` and establish nothing.** Re-home the 91 sequences, prove the
   six-target sweep is unchanged, land. `esi` is now dead but reserved. This
   phase is verifiable on its own and touches no relocation.
2. **Establish the GOT base** in the prologue (`call/pop` thunk +
   `add $_GLOBAL_OFFSET_TABLE_`), save/restore `esi` as callee-saved, emit
   `R_386_GOTPC`. Still no addressing change: the base is computed and unused,
   so the object is byte-identical except for the prologue and it can be
   diffed as such.
3. **Convert the addressing**, family by family from the table above, watching
   the `.text` absolute count fall from 1482. The ModRM family is one
   expression and 606 sites; take it first because it is length-preserving.
4. **Add the `test-emit-obj` i386 row** asserting `.text` carries no absolute
   relocation — scoped by relocation SECTION as the x86-64 row is, so the
   `.rel.init_array` entry against the `.text` symbol is not miscounted.

**The row lands in phase 4, not phase 1.** The ticket already says why: a red
assertion on a property that has never held costs Track T's signal for everyone
and buys information this census already gives.

## RE-CENSUS AFTER `e95538346`, AND THE OBJECT CENSUS IS A SAMPLE (2026-09-01, frankC)

Re-taken against frankA's `EmitStaticLitHandle386`, which changed how string
literals are addressed on i386:

| | sites | shapes | `b8` | `68` |
| --- | ---: | ---: | ---: | ---: |
| at `91a139b70` | 1482 | 24 | 92 | 100 |
| at `2d17f449f` | **1450** | **23** | **160** | **0** |

`68 push imm32` — my most invasive family, the only one needing
`push ebx; add dword [esp], d32` at +3 bytes — **went to zero**, replaced by
`b8 mov eax,imm32` at +1. That looks like the hardest quarter of phase 3
evaporating.

**IT IS NOT, AND BELIEVING IT WOULD HAVE BEEN A REAL ERROR.** The shape is gone
from these three OBJECTS, not from the compiler. `grep 'EmitB($68)'` over
`ir_codegen386.inc` finds 26 sites, of which **nine push a DATA ADDRESS**:

```
1762  push arg1 = desc          GetOrAllocSymRTTI
1800  push src                  string-literal fallback
2266  push desc                 GetOrAllocNodeDynDesc
2996  push desc                 GetOrAllocSymRTTI
4423  push arg1 = desc          GetOrAllocNodeDynDesc
4499  push src                  string-literal fallback
4655, 4664, 4673  push desc     RECORD_RTTI_DATAREF_BASE
```

RTTI descriptors, dynamic-array descriptors, record RTTI. The three test
objects simply do not exercise those paths on i386. Had I read the zero as
coverage, the `+3` rewrite would not have been written and the first program
using RTTI on i386 would have carried an absolute relocation the new assertion
was supposed to forbid — after the assertion had gone green.

### So phase 3 must be driven by an EMITTER census, not an object census

An object census SAMPLES: it reports the shapes the programs I happened to
compile contain. The authoritative population is the emitter, and it is not one
file — `EmitDataRef`/`EmitGlobRef` are called from `ir_codegen386.inc` (33/82),
`ir_codegen.inc` (27/43) and `emit.inc` (10/11), with `coroutine_emit.inc`,
`exception_emit.inc` and `asmenc.inc` also able to emit for i386.

**The method is already recorded in this repo**, in `EmitGlobRef`'s own comment
for the x86-64 twin: *"Re-measured over a population that CAN contain it
(instrumenting the emitter, building --threadsafe)"*. Instrument the choke
point, print the preceding bytes, compile a broad corpus, union the shapes.
That is phase 3's first step, ahead of any rewriting.

**Three censuses, three different answers, each honestly taken:** the C object
alone reports 19 shapes; three objects report 24; three objects after an
unrelated string-literal change report 23 — and the true count is whatever the
emitter can produce, which none of them measured. Every one of those numbers
would have read as complete.

## CORRECTION: THE COST I RECORDED FOR `esi` WAS WRONG (2026-09-01, frankC)

The register decision above says the cost is *"91 esi sequences ... all
short-lived, none live across an IR node ... each needs re-homing onto `edi` or
a spill"*, and calls it the smallest of the three options.

**The choice survives. The cost sentence does not, and it was the load-bearing
half.** Measured: **70 of the 91 `esi` lines have `edi` within ±6 lines**, and
they are genuinely co-live, not merely adjacent —

```
mov al, [esi] / mov [edi], al / inc esi / inc edi      a byte-copy loop
{ Clobbers ebx, ecx, esi, edi. }                       the 64-bit divide's own comment
```

So *"re-home onto `edi`"* is unavailable for the large majority of sites, and I
wrote it as though the two registers were interchangeable spares. **There is no
free register on i386 here at all**: `eax` `ecx` `edx` `ebx` `esi` `edi` are all
in the working set and `ebp`/`esp` are fixed. Any choice of base register costs
real code motion; `esi` is still the cheapest and the byte-addressability
argument is untouched.

### The technique is SAVE/RESTORE, not re-homing

Re-homing was the wrong shape to reach for. The sequences that clobber the base
register are **self-contained emitted blocks** — a copy loop, a divide core, a
formatting helper — so each one wraps itself:

```
push esi   ...the existing sequence, unchanged...   pop esi
```

Local, mechanical, and it leaves the platonic code alone instead of rewriting 70
working sequences into a register they were not written for. Cost is two bytes
and two memory accesses per clobbering sequence, paid only where the clobber
happens. It is also what makes the sequences reviewable: the diff is a wrapper,
not a rewrite.

**This is the correction that matters for whoever implements phase 1**, because
"rename esi to edi in 91 places" is a plausible-looking day of work that
produces a backend which fails wherever both were live — and the failures would
be in string copies and 64-bit division, i.e. everywhere, but only in programs
that reach those paths.

## THE EMITTER CENSUS, AND IT FOUND THREE SHAPES NO OBJECT CENSUS HELD (2026-09-01, frankC)

`PXXDBG=a.i386reloc` (added to `emit.inc`) prints the eight bytes preceding
every 32-bit absolute fixup on i386, at the `EmitDataRef`/`EmitGlobRef` choke
point. Run over eight programs chosen to REACH what the objects missed — dyn
arrays, RTTI/typinfo, a class hierarchy, records — plus a `--threadsafe` build:

```
11645 emitter sites, against 1450 from the three-object census
```

Each site is matched against the 24 known shapes and **anything unmatched is
reported**, which is the whole instrument: a census that can only count what it
already knows is a tally, not a measurement.

Three unmatched, all confirmed by assembling them:

| N | tail | is | family |
| ---: | --- | --- | --- |
| 74 | `c7 00` | `mov DWORD PTR [eax], imm32` | **NEW — address as an IMMEDIATE inside a store** |
| 42 | `a2` | `mov ds:d32, al` | moffs, the BYTE sibling of `a1`/`a3` |
| 4 | `0f b7 05` | `movzx eax, WORD PTR ds:d32` | plain ModRM, the 16-bit sibling of `0f b6 05` |

`0f b7 05` and `a2` are new members of families already planned for. **`c7 00`
is a family that did not exist in the plan**, and it is the hardest one yet:
the data address is the instruction's IMMEDIATE, not its displacement, and the
base register is already `eax`, so there is nothing to fold the GOT base into.
It needs `lea <scratch>, [esi+d32@GOTOFF]` then `mov [eax], <scratch>` — the
first shape in this whole census that requires a scratch register the emitter
must find. 74 sites.

Had phase 3 been written from the object census, it would have been written
without an entry for that, and `-Wl,-z,text` would still have refused the link
after the assertion certifying otherwise had gone green.

### Neither census is complete alone, and that is the durable point

Six of the 24 object-census shapes — `f0 0f b1 0d`, `ff 14 25`, `8b 05`,
`39 35`, `ff 05`, `ff 0d` — were **not reached** by the eight-program emitter
corpus. Adding a `--threadsafe` run covers them and produces **zero further
unknowns**, so the union stands at **27 shapes**.

- an OBJECT census is bounded by which programs you compiled;
- an EMITTER census is bounded by which programs you compiled, *but reports what
  it could not classify*, which is the property that makes it extensible;
- neither is bounded by the compiler's actual reachable set.

So the honest claim is **"27 shapes across these axes, with an instrument that
announces a 28th"** — not "27 shapes". The probe stays in the tree for exactly
that reason: whoever does phase 3 re-runs it, and a new shape says so instead of
silently becoming an absolute relocation.

## NO GOT IS NEEDED, AND TWO EARLIER ENTRIES IN THIS FILE ARE WRONG (2026-09-01, frankC)

Everything above assumes the fix is GOTOFF addressing off a GOT base, because
that is what gcc does on i386 and what the re-scoping paragraph asserted. **It
is not necessary here, and the cheaper scheme was never tested against.**

Our `.data`/`.bss` symbols are section-local and not exported, so nothing can
preempt them and no indirection is required. A **PC-relative anchor** reaches
them with a link-time-constant displacement:

```asm
        call    .L1
.L1:    popl    %esi                    # esi = the address of .L1
        movl    myval-.L1(%esi), %eax   # R_386_PC32 against .data
```

Assembled, linked and RUN, rather than argued:

```
.rel.text:  00000008  R_386_PC32  .data        <- not R_386_32
gcc -m32 -pie -Wl,-z,text  ->  LINKED CLEAN    <- the link that refuses today
./pcrel                    ->  exit 42
```

`-Wl,-z,text` is the exact link this ticket exists to unblock, and it accepts
this with no GOT, **no `_GLOBAL_OFFSET_TABLE_` symbol, and no `R_386_GOTPC`.**
That deletes a whole phase: the ELF writer needs one new relocation TYPE and no
new section, no GOT construction and no symbol synthesis.

### The addend, measured rather than derived

SHT_REL has no addend field, so it lives in the four bytes being patched. The
assembler stored **3**, and `A = F - anchor` predicts `8 - 5 = 3`. The linker
then computes `S + A - P = S + 3 - 8 = S - 5`, which is `S - anchor` — the
displacement wanted. Both `F` (the fixup's offset in `.text`) and the anchor's
offset are known at emit time, so the emitter can compute the addend directly.

### CORRECTION 1 — the ModRM constant in this file is for the WRONG REGISTER

The census section says the twelve-shape family collapses to

```
modrm := (modrm and $38) or $83
```

`$83` is `mod=10, rm=011` — **`ebx`**, written before the base register was
decided and never revisited when the decision came out `esi`. The correct
constant is **`$86`** (`mod=10, rm=110`), confirmed by assembling
`mov eax, [esi+d32]` → `8b 86` and `mov edx, [esi+d32]` → `8b 96`.

The expression's SHAPE is right and the reg field is still preserved; only the
literal is wrong. It is exactly the kind of constant that would have been
copied into the implementation verbatim, produced `[ebx+disp32]` against an
anchor held in `esi`, and read from a register that happens to hold a live
value — a plausible wrong address rather than a crash.

### CORRECTION 2 — "i386 has no PC-relative data addressing" is misleading

That sentence appears in the summary and the re-scoping paragraph, and it is
true of the ADDRESSING MODES: there is no `[eip+disp32]` on i386. It was then
used to conclude that a GOT base register is required, which does not follow —
`call/pop` puts the PC in a general register, and every addressing mode works
off that. The correct statement is that i386 needs an explicit anchor
instruction where x86-64 has `rip`; what it does NOT need is a GOT.

## Phases, revised

1. ~~emitter census~~ **done** (`abc5b9979`, `PXXDBG=a.i386reloc`).
2. **Anchor + `R_386_PC32` in the writer.** Emit `call/pop` into `esi` per
   function, `push esi`/`pop esi` around the sequences that clobber it, and
   teach `writeELFRel386General` the new relocation type. Convert NOTHING yet:
   the anchor is computed and unused, so every program must behave identically
   and the absolute count must not move. That is a real assertion, and it is
   the one this phase is verified by.
3. **Convert family by family**, watching `.text` absolutes fall from 1450 and
   re-running the emitter probe after each so a 28th shape announces itself.
4. **The `test-emit-obj` i386 row LAST**, scoped by relocation SECTION.

## PHASE 3'S REAL PROBLEM IS KEEPING THE ANCHOR ALIVE, AND IT IS NOT SOLVED HERE (2026-09-01, frankC)

The anchor is emitted and inert (`e1209443d`). Converting even ONE reference to
use it requires `esi` to still hold the anchor at that point, and **that is the
whole remaining difficulty** — the addressing rewrites are a table lookup, and
this is not.

`esi` appears in **13 procedures** of `ir_codegen386.inc`:

```
IREmitNode386          53      <- the problem
EmitUDivMod64Core_386   6      EmitArgvToFixedString386  5
EmitIoLockStubs386      4      EmitwriteIntW386          4
EmitwriteUInt64_386     4      IREmitMachineCode386      4  (2 are the anchor itself)
EmitArgvToAnsiString386 3      EmitIDivMod64Core_386     3
EmitBinop64_386         3      EmitSignalRuntime386      2
EmitWriteCStr386        2      EmitwriteUIntW386         1
```

The twelve helpers are self-contained emitted blocks: one `push esi` / `pop esi`
per procedure and they are done. **`IREmitNode386` is not one block** — its 53
uses are spread across expression arms, so the wrapper has to go per-arm, and
the failure mode of missing one is a silently wrong ADDRESS, not a crash.

### Three strategies, and none of them is obviously right

1. **`push esi` / `pop esi` per clobbering sequence.** Local invariant: a
   sequence restores what it found. Cheapest to review. Missing a site gives a
   wrong address.
2. **Re-anchor after each clobber** — re-emit `call/pop` and update
   `X386PicAnchor`, since displacements are computed against whatever the
   current anchor is and the emitter knows the new offset. No save/restore at
   all. But correctness now depends on the emitter's MODEL matching the emitted
   code, which is a worse thing to get wrong than a missing push.
3. **Anchor in a frame slot, loaded before each reference.** Removes every
   cross-sequence invariant — the anchor cannot be stale because it is reloaded.
   **But it clobbers `esi` at the reference point**, which is inside whatever
   sequence contains the reference, so it reintroduces the same problem one
   level down. It only works if no `esi`-using sequence contains a data
   reference, which is NOT established.

**Strategy 3 looked like the clean answer for several minutes and is not**; it
moves the conflict rather than removing it. That is recorded because it is the
one a fresh reader will reach for.

### What has to be measured before choosing

Whether any of the 13 `esi`-using sequences CONTAINS a data reference — i.e.
whether the sets overlap at all. If they are disjoint, strategy 3 is safe and
is much the simplest. If they overlap, strategy 1 is the only one whose failure
mode is bounded. **That is one measurement and it decides the phase**, which is
exactly the shape of question this ticket has been answering by measuring rather
than arguing; I am stopping at the boundary rather than picking on taste.

`esi` is callee-saved in i386 SysV, so ordinary CALLS already preserve it. The
problem is entirely our own emitted sequences.

### THE DECIDING MEASUREMENT, TAKEN — and the answer is "both mechanisms, in 12 named places"

**Do the `esi`-using sequences contain data references?** Yes, so **strategy 3
is out**: reloading the anchor into `esi` at a reference point would clobber a
live `esi` belonging to the sequence around it.

Per PROCEDURE, 8 of the 13 do both. **That figure overstates the problem and I
nearly stopped at it.** Refined to case-arm granularity inside `IREmitNode386`,
where 53 of the 55 `esi` mentions live:

```
53 case arms:   7 esi only    16 data-ref only    5 BOTH
```

The five: `IR_STORE_SYM`, `IR_CALL`, `IR_STORE_MEM`, `IR_COPY_REC_MANAGED`,
`IR_SET_BINOP`. So the interleaving problem is **12 places**, not 53 arms and
not "the whole dispatcher":

| where | treatment |
| --- | --- |
| 7 arms + 5 helpers using `esi` with NO data ref | `push esi`/`pop esi` wrapper, nothing else |
| the 5 arms above + 7 helpers doing BOTH | per-site: the sequence must re-anchor before the reference it contains, or move its own use off `esi` |

Helpers in the second group: `EmitArgvToFixedString386`, `EmitSignalRuntime386`,
`EmitIoLockStubs386`, `EmitwriteIntW386`, `EmitwriteUIntW386`,
`EmitIDivMod64Core_386`, `IREmitMachineCode386`.

**So neither strategy 1 nor strategy 2 alone — both, and the boundary between
them is this list.** Strategy 1 for the clean sequences because its failure mode
is local; strategy 2 only inside the twelve, where a wrapper cannot help because
the reference is INSIDE the sequence that repurposed the register.

*Precision of this count*: the arm splitter matches `IR_xxx:` labels and counts
a bare occurrence of `esi`, so comments mentioning `esi` inflate it and a nested
case could be mis-split. It is a narrowing instrument, not an exact one — it
takes the work from "53 arms, unknown" to "5 named arms, verify each". Verify
each before wrapping it.


## 2026-09-01 — phase 3, family 1: loads. Landed `b64341130`

`TryI386PcRelLoad` in `emit.inc`, called from the i386 arm of `EmitDataRef` and
from a new `else if` arm of `EmitGlobRef`. Converts an absolute `[disp32]` LOAD
just emitted by the caller into

```
mov  dest, [ebp+picslot]
mov  dest, [dest+disp32]        <- R_386_PC32, addend symOffset + (fieldPos - anchorPos)
```

**Dest is its own base**, which is what removes the liveness problem the earlier
esi plan had: the instruction is a load *into* dest, so dest is dead at that
point by construction. Refuses `esp` (SIB) and `ebp` (mod=10 rm=101 collides
with the form being left) as bases, and refuses every opcode not on the list.

Addend patching is in `elfwriter.inc`'s SHT_REL fill, split into a PC-relative
and an absolute arm per fixup array. `PicDelta` is 0 on every absolute site so
the arms could be one expression; they are kept apart because `+ PicDelta` on a
row typed `R_386_32` would read as if the addend had a PC term there.

### Two things this cost, both worth remembering

**The anchor's "verified inert" claim was too wide.** It had been checked against
`test-c-abi-mixed-link`, and *every row of that gate is a procedure*. The main
body is emitted with no `push ebp; mov ebp,esp` at all, so `mov [ebp+slot], esi`
there writes through whatever `ebp` the loader left — SIGSEGV at the store, at
`0x807163d`, in the body that starts `mov eax,2; call`. The anchor is now gated
on `CurProc >= 0`; the frameless body's references stay absolute, and the
converted count did not move, so that body had no convertible site anyway.

**Both existing gates pass against a deliberately corrupted compiler.** With
every PC-relative addend shifted by `+0x30000000`, `test-emit-obj` rows 4b and
4d PASS and `test-c-abi-mixed-link` PASSes on both targets. `+8` passes too.
They are not blind because the construct is absent — the objects carry 114
converted sites — but because *nothing on the executed path is one of them*.
This is a distinct shape from an empty population: the census is right, the
coverage is real, the execution is nil, and no assertion in either gate can tell.

`test/i386_pcrel_globals.c` + `_host.c` is the answer: every global is read and
its value asserted, one row per converted opcode with signed and unsigned kept
apart, plus an assertion that the object carries a nonzero `R_386_PC32` count so
a conversion that quietly stopped firing cannot pass. It segfaults against the
`+0x30000000` compiler. Wired into `test-emit-obj` as row 4d2.

### Next

Family 2 is the stores (`89`, `88`, `C7`), the largest remaining group. Unlike a
load they must keep their source operand, so the scratch has to be found rather
than reused: `push`/`pop` around the pair is locally correct and costs 2 bytes.
Re-run `PXXDBG=a.i386reloc` after each family so a 28th shape announces itself,
and add the "no absolute relocations in .text" assertion LAST, scoped by
relocation SECTION rather than by symbol name.
