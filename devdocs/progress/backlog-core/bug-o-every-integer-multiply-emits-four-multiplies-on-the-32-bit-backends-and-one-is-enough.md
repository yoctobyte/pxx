---
slug: bug-o-every-integer-multiply-emits-four-multiplies-on-the-32-bit-backends-and-one-is-enough
track: A
tags: [O]
type: bug
prio: 30
status: open
owner: ""
created: 2026-09-24
found-by: frank (split out of the muluh ticket, whose wall half is closed)
blocked-by: []
summary: "MECHANISM: integer binops are typed tyInt64 with tyInteger operands AND a tyInteger destination, so every 32-bit backend lowers `a * b` as a full 64x64 expansion -- low product, high product, and two cross products -- and then stores only the low word. On the 32-bit targets that is FOUR multiply instructions and two adds where ONE would do, at every declared width; on x86-64 a 64-bit imul is one instruction, so the cost is invisible on the primary target and paid only by i386, arm32, riscv32 and xtensa. Measured on riscv32 by counting multiplies in the executed trace: Integer*literal, Integer*Integer, Int64*Int64 and SmallInt*SmallInt all emit 4, against a 0-multiply negative control whose only change is `+` for `*`. THE FIX IS CONSUMER-AWARE NARROWING AT LOWERING TIME -- emit only the low multiply where the result is provably consumed at <=32 bits -- and NOT narrowing the binop's TYPE. The type is load-bearing and that half is CLOSED: ir_codegen.inc's EmitOvfCheckNarrowX64 documents that the wide evaluation is what makes the mathematically exact result available, which is what {$Q+} overflow detection is built on as a range test, so narrowing the type would silently remove overflow detection on every target to save instructions on four. AND IT IS NOT ONLY SIZE AND SPEED -- ON HOSTED XTENSA IT IS A RUNTIME REQUIREMENT: a plain `Integer * Integer` emits `muluh` and SIGILLs on every stock qemu-xtensa core, so it cannot run at all without `--xtensa-soft-mulhigh` (measured with a Halt-only probe, rc=132 unflagged against rc=3 for both the `+` control and the flagged build, so the fault is the multiply and the flagged product is correct). A narrowed multiply emits one `mull` and no `muluh`, so this fix would make ordinary integer code run unflagged -- the strongest argument the ticket has. THE CONDITION THAT RETIRES IT: an integer multiply whose result is consumed at 32 bits emits one multiply instruction on all four 32-bit backends, with the {$Q+} overflow rows still green and a row asserting the product's VALUE (a narrowing that computes the wrong product would pass an instruction count)."
---

# Every integer multiply emits four multiplies on the 32-bit backends, and one is enough

Split out of
[[bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it]]
on 2026-09-24. That ticket's headline — hosted xtensa cannot multiply — is
**closed**: `--xtensa-soft-mulhigh` ships and predates it. What survives is this,
and it is a cost rather than a wall, on four targets rather than one.

## The mechanism

`PXXDBG=a.ir:Mul` for `q := i * j`, all three declared `Integer`:

```
0: load_sym  tk=1  [sym=i]      tk=1  = tyInteger  (4-byte signed)
1: load_sym  tk=1  [sym=j]
2: binop  a=0 b=1 c=72 tk=13    tk=13 = tyInt64    (8 bytes)
3: store_sym a=4 b=2 tk=1 [sym=q]
```

Operands `tyInteger`, destination `tyInteger`, **binop `tyInt64`**. So the
backends are asked for a 64-bit product and dutifully build one:

| | sequence |
| --- | --- |
| riscv32 | `mul t2,t0,a0` / `mulhu t3,t0,a0` / `mul t4,t0,a1` / `mul t5,t1,a0` |
| xtensa | `mull a8,a4,a2` / `muluh a9,a4,a2` / `mull a10,a4,a3` / `mull a11,a5,a2` |

and the high half is then **dead**, because the store is one 32-bit word:

```
add a1,t3,t4     ┐ high half assembled...
add a1,a1,t5     ┘
mv  a0,t2
lw  t0,8(t0)
sw  a0,0(t0)     <- only a0 (the LOW word) is stored; a1 is never used
```

## What is measured

Multiply instructions in the **executed trace** on riscv32:

| source | multiplies emitted |
| --- | --- |
| `Integer * literal` | 4 |
| `Integer * Integer` | 4 |
| `Int64 * Int64` | 4 |
| `SmallInt * SmallInt` | 4 |
| **negative control** — same program, `+` instead of `*` | **0** |

The control is what makes the count a measurement of the expression rather than
of the RTL around it.

**Population and tree:** four hand-written programs, riscv32, compiler at
`1b158869e9`. The instruction sequences above are xtensa and riscv32; i386 and
arm32 are asserted here **by the same IR type and not by measurement** — the IR
hands every 32-bit backend the same `tyInt64` binop, so the shape is predicted,
not observed. Measure them before quoting a number for them.

## Why this is free on the primary target

A 64-bit `imul` on x86-64 is one instruction, so x86-64 pays **nothing** and
sees nothing. This is CLAUDE.md's measured-on-x86-64 blind spot arriving in a
performance decision instead of a correctness one: the dev loop, `gate.sh quick`
and the pin all run on the target where the cost does not exist.

## The fix, and the one that must NOT be done

**Do:** narrow at **lowering** time — emit only the low multiply where the
result is provably consumed at <= 32 bits. The binop's type is untouched, so
nothing downstream loses the wide value where it is genuinely used wide.

**Do not: narrow the binop's TYPE.** That half is closed and this section exists
to keep it closed. `ir_codegen.inc`, `EmitOvfCheckNarrowX64`:

> *The binop was computed at 64-bit register width on sign/zero-extended
> operands, so rax holds the mathematically exact result and the 64-bit OF/CF
> never fire for a 32-bit wrap (bug-a-qplus-misses-32bit-overflow). The check is
> therefore a range test.*

So the wide evaluation is **what `{$Q+}` overflow detection is built on** — the
exact result exists and the check re-extends the low width and compares.
Narrowing the type removes that on **every** target to save instructions on
four. It is the integer analogue of CLAUDE.md's *"DOUBLE IS THE NATIVE
EVALUATION TYPE … an expression being typed or evaluated at double width is the
architecture, not a defect"*, and unlike the float case it has a live mechanism
depending on it.

## Why it is worth more than a cycle count

Code size on a flash-constrained target. Every integer multiply in an ESP image
carries three surplus multiplies and two adds, and image size is an active
constraint — see the bare-image size caps work. That is a better argument for
doing this than the cycle count is, and it is the one to price.

## Positive control for whoever fixes this

Two rows, because an instruction count and a correct product are different
claims:

1. **The count** — an `Integer * Integer` whose result is stored to an `Integer`
   emits **one** multiply on each of the four backends. The negative control
   above (`+` for `*`) keeps the counter honest.
2. **The value** — assert the PRODUCT, not the exit status. A narrowing that
   picks the wrong half, or that mis-signs, computes a wrong product and would
   pass row 1 perfectly.

And re-run the `{$Q+}` overflow rows: they are the population that would be
silently broken by doing this the wrong way, and they are the reason the wrong
way is spelled out above.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]

## 2026-09-24 (frank, frankb-8e) — the narrowing has a home in the IR, the gate is sound, and it is sound BECAUSE OF A CONDITION IN ANOTHER FILE

Read-only investigation, no code change. Recorded because the ticket recommended
consumer-aware narrowing without saying where the consumer's width is known, and
it turns out to be in the IR dump the ticket already prints.

### The consumer's width is already in the IR

From the ticket's own `PXXDBG=a.ir:Mul` dump:

```
2: binop  a=0 b=1 c=72 tk=13    tk=13 = tyInt64
3: store_sym a=4 b=2 tk=1 [sym=q] tk=1  = tyInteger
```

The store node carries `tk=1` and names the binop as its value operand, so
"is this result consumed at <= 32 bits" is not a dataflow problem needing new
machinery — the consumer is a node whose `tk` says so.

### The routing site, and both emitters already exist

`ir_codegen_riscv32.inc:2587` (the `if (op <> Ord(tkIn)) and` at the head of the 64-bit routing test) takes the 64-bit path when the node's OWN `tk` is
64-bit, which is the disjunct that fires for `Integer * Integer`:

```pascal
if (op <> Ord(tkIn)) and
   (Is64BitRISCV32(IntToTypeKind(IRTk[node])) or
    Is64BitRISCV32(IntToTypeKind(IRTk[left])) or
    Is64BitRISCV32(IntToTypeKind(IRTk[right]))) then
  EmitBinop64RISCV32(...)
```

The narrow path is not something to build: `IREmitNodeRISCV32` is the 32-bit
emitter and sits directly below. The change is a routing condition, not a new
lowering.

### THE GATE IS `IRIVal[node] <> 1`, AND IT IS SOUND — I FIRST WROTE THAT IT WAS NOT

The safety argument is that `{$Q+}` needs the wide product, and
`ir_codegen.inc:6106` says why in its own words: *"the binop was computed at
64-bit register width on sign/zero-extended operands, so rax holds the
mathematically exact result and the 64-bit OF/CF never fire for a 32-bit wrap.
The check is therefore a range test."*

I then noticed that the range test is applied at the **store**
(`ir_codegen.inc:8591`, the `if (IRB[node] >= 0) and (IRKind[IRB[node]] = IR_BINOP)` guard) and not at the binop, keyed on
`Syms[symIdx].TypeKind` — the DESTINATION's type — and wrote this section up as
a trap: a binop whose own flag is clear could still feed a store that
range-tests it, so narrowing would silently reintroduce
`bug-a-qplus-misses-32bit-overflow`. **That was wrong, and reading the guard is
what refuted it.** The store-side check is itself conditional on the binop's own
flag:

```pascal
if (IRB[node] >= 0) and (IRKind[IRB[node]] = IR_BINOP) and
   (IRIVal[IRB[node]] = 1) and
   TypeIsOrdinal(Syms[symIdx].TypeKind) and ... then
  EmitOvfCheckNarrowX64(Syms[symIdx].TypeKind);
```

So there is no store that range-tests an unflagged binop, and `IRIVal[node] <> 1`
is a sufficient gate. It was one `sed` from being a confident, well-argued,
wrong warning in a ticket.

### THE REAL HAZARD IS THE COUPLING, AND NOTHING AT EITHER END NAMES IT

What the false alarm did find is worth keeping, because it is the thing that
makes this fix fragile rather than the thing that makes it wrong:

**Narrowing at the routing site is correct only because of a condition in a
different file, and neither site says so.** The gate lives in
`ir_codegen_riscv32.inc` (and three sibling backends); the property that makes it
sound lives in `ir_codegen.inc:8592`, the `IRIVal[IRB[node]] = 1` conjunct of that guard. If anyone ever
makes the store-side range test unconditional — which is a perfectly reasonable
thing to want, since a range test that only fires for flagged binops looks like
an oversight — then every narrowing gate in four backends silently becomes
unsound, and the symptom is `{$Q+}` quietly missing 32-bit wrap on the 32-bit
targets only.

So whoever implements this owes a comment at BOTH ends naming the other, and the
`{$Q+}` row below is what would catch it. This is the ordinary
two-spellings-of-one-invariant shape, except the two spellings are a gate and
the reason the gate is allowed.

### What a correct attempt needs, in order

1. A predicate over the node's CONSUMERS ("every consumer takes <= 32 bits"),
   plus the `IRIVal[node] <> 1` gate above.
2. Do it as a shared IR pass, not four routing conditions — `ir-as-substrate`,
   and it fixes all four 32-bit backends at once.
3. **IT CHANGES x86-64 OUTPUT AND THEREFORE THE FIXEDPOINT.** On x86-64 a 64-bit
   `imul` is one instruction so there is no instruction win, but a narrowed binop
   still emits a different encoding, so `compiler/pascal26` changes and the
   self-host chain must converge. Do not read a changed binary as a defect.
4. Breadth, not `quick`: this is integer codegen on every target including the
   one that builds the compiler.

### The assertion class, because an instruction count cannot see either failure

The ticket already asks for a VALUE row beside the instruction count. The
investigation above adds the third row and the reason for it: a narrowing that
computes the wrong product passes the count; a narrowing that breaks the `{$Q+}`
coupling passes **both** the count and the value row. So the third row is a
`{$Q+}` program whose multiply wraps and must still trap — and it is also the
regression test for the coupling hazard above, which is the only thing that would
catch a future change to the store-side guard.

### i386 AND arm32 ARE NOW MEASURED, AND THE PREDICTED 4 IS WRONG FOR BOTH — IT IS 3

The ticket flags its own i386/arm32 rows as *"asserted here by the same IR type
and not by measurement ... Measure them before quoting a number for them."*
Measured, and the caveat earned its place:

| target | multiplies | sequence | source |
| --- | ---: | --- | --- |
| riscv32 | 4 | `mul` `mulhu` `mul` `mul` | ticket, 2026-09-24 |
| xtensa | 4 | `mull` `muluh` `mull` `mull` | ticket, 2026-09-24 |
| **i386** | **3** | `imul` `imul` `mull` | measured below |
| **arm32** | **3** | `mul` `mul` `umull` | measured below |

**The mechanism is identical and the COUNT is an ISA property**, which is the
refinement: the expansion always needs lo*lo at full width plus two 32-bit cross
products. Where the ISA has a single widening multiply that produces both halves
(x86 `mull`, ARM `umull`) that is 3 instructions; where lo*lo needs two
(riscv32 `mul`+`mulhu`, xtensa `mull`+`muluh`) it is 4. The dead high half and
the wasted cross products are the same on all four, so the ticket's argument is
untouched — only its number was over-general.

i386, the whole sequence, with the store that discards the high half:

```
247: cltd                  ; sign-extend i to edx:eax
248: push %edx / push %eax ; spill i as a 64-bit pair
24f: cltd                  ; sign-extend j
252: imul (%esp),%ecx      ; j.hi * i.lo      <- 1
258: imul 0x4(%esp),%eax   ; j.lo * i.hi      <- 2
25d: add %eax,%ecx
261: mull (%esp)           ; edx:eax = j.lo * i.lo  <- 3 (both halves)
264: add %ecx,%edx         ; high half assembled...
269: mov %eax,0x8052418    ; ...and only eax is stored
```

arm32: `mul r1, r2, r1` / `mul r3, r3, r0` / `umull r3, r12, r2, r0`, then
`add r1, r1, r3` / `add r1, r12, r1` assembling a high word that `str r0, [r1]`
never writes.

**Population, tree and oracle**, because a bare count is not re-derivable: two
hand-written programs (`q := i * j` and, as the negative control, the same
program with `+`), all three variables `Integer`, `i := 7` and `j := 9` as
literals — verified NOT constant-folded, since both targets really do emit the
multiplies. Compiler `bb681c88af9f` at tree `c4d759f5c5`. The number quoted is
the DELTA between the two programs, so the RTL around the expression cancels.

### TWO INSTRUMENT TRAPS, AND THE SECOND ONE ANSWERS ZERO WITHOUT ERRORING

Both cost real time here and neither produced an error.

1. **`objdump -d` disassembles NOTHING on a pxx binary and does not say so.**
   pxx writes its own ELF with **no section headers**, so `objdump -d` prints
   three lines — the filename and the format it correctly identified — and no
   code. A mnemonic grep over that answers **0**, which reads as "no multiply".
   `llvm-objdump -D` disassembles by `PT_LOAD` segment and works; that is why
   `pxx_regs` uses llvm-objdump, and the reason is worth knowing rather than
   inheriting. `objdump -D -b binary -m i386` also works but disassembles the
   ELF header as code and turned the string `builtinheap` into a plausible
   `imul $0x6165686e,...` — a false hit the differential control cancelled and a
   bare count would not have.

2. **AN ARM MNEMONIC COUNT ANSWERS 0 FOR A BINARY FULL OF MULTIPLIES UNLESS THE
   TRIPLE IS RIGHT.** Same file, same tool, one flag:

   | invocation | count |
   | --- | ---: |
   | `llvm-objdump-21 -D` (no triple; reads elf32-littlearm) | **0** |
   | `--triple=arm-none-eabi` | **0** |
   | `--triple=armv5te-none-eabi` | **0** |
   | `--triple=armv7a-none-eabi` | **3** |

   Three of four answer zero, and the wrong triple does not error — it prints
   `<unknown>` for each undecoded word, so the mnemonic grep finds nothing and
   the absence looks like a finding. I only caught it by DIFFING the two
   disassemblies and seeing three `<unknown>` words where the control had
   `adds`/`adc`; the count alone said arm32 emits no multiply at all. Hand-decoding
   `e08c3092` as `umull r3, r12, r2, r0` and then confirming it with the correct
   triple is what closed it — a hand-decode is a second source, and it was needed
   because the first source's failure mode is silence.

   **So do not count mnemonics in an ARM disassembly without asserting the
   disassembler decoded the instructions**, e.g. that `<unknown>` does not appear
   in the region under test. That assertion is the positive control this
   measurement was missing for its first three attempts.

### THE CONSEQUENCE THAT RAISES THIS TICKET'S VALUE: ON HOSTED XTENSA, `Integer * Integer` CANNOT RUN WITHOUT `--xtensa-soft-mulhigh`

Measured behaviourally, because no disassembler on this box can read an xtensa
pxx binary (see the trap below). Three rows, each of which discriminates:

| program | flag | rc | meaning |
| --- | --- | ---: | --- |
| `q := i * j; if q = 63 then Halt(3) else Halt(4)` | none | **132** | SIGILL — `muluh` emitted and no qemu core implements it |
| `q := i + j; if q = 16 then Halt(3) else Halt(4)` | none | **3** | the negative control runs, so the SIGILL is the multiply |
| `q := i * j; ...` | `--xtensa-soft-mulhigh` | **3** | the flag fixes it AND `q = 63`, so the product is right |

`Halt(3)` versus `Halt(4)` rather than a printed value, deliberately: the
expected rc differs from the failure rc and from any default, so the row cannot
pass by accident, and the value is asserted rather than just the survival.

**So the narrowing in this ticket is not only a size/speed win — it removes a
RUNTIME REQUIREMENT.** A narrowed `Integer * Integer` emits one `mull` and no
`muluh`, so ordinary integer code would run on a stock qemu-xtensa core without
any flag. That connects this ticket to
[[bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it]],
which was closed on the grounds that the mitigation ships: the mitigation is a
FLAG the user must pass, and this fix would make the common case not need it.
Worth weighing when ranking, and it is the strongest argument the ticket has.

### A FOURTH VACUOUS CONTROL, IN MY OWN WORK, TWENTY MINUTES AFTER ENDORSING THE SECTION ABOUT IT

The first version of the test above used `WriteLn(q)` to observe the product.
Result: the multiply program died with SIGILL **and so did the `+` control.**
Both arms failed identically for a reason unrelated to the question — the RTL's
`WriteLn` integer path itself needs `muluh` on xtensa — so the comparison was
vacuous and would have "confirmed" the multiply hypothesis on evidence that
said nothing about multiplies.

This is franks-5b's class exactly (`58a717e54a`), reproduced by someone who had
read that section, agreed with it in writing, and argued about its promotion,
within the hour. Recorded because that is the finding: **knowing this class does
not prevent it.** What caught it was the control failing, which is the one thing
a vacuous control does visibly — had `WriteLn` needed no multiply on some other
target I would have shipped the conclusion.

Separately true and worth its own line: **any hosted xtensa program that PRINTS
an integer needs `--xtensa-soft-mulhigh`**, independent of anything in the user's
own arithmetic. That is consistent with every existing `test-xtensa` row passing
the flag, and it is a larger surface than the multiply itself.

### THE THIRD DISASSEMBLER TRAP, AND IT IS THE SAME ONE AGAIN

`llvm-objdump-21` prints `file format elf32-xtensa` and
`Disassembly of section PT_LOAD#0:` for an xtensa pxx binary and **cannot
disassemble it** — xtensa is not in its registered targets. So a mnemonic count
answers `muluh=0 mull=0`, which reads as "no multiply is emitted" for a program
that dies on an unimplemented multiply. Three instruments in one investigation,
all answering 0 about a binary full of multiplies, none erroring:
`objdump -d` (no section headers), `llvm-objdump` with the wrong ARM triple
(`<unknown>` per word), and `llvm-objdump` on xtensa (unsupported target). **The
general form is that a disassembler reports on the FORMAT it recognised and is
silent about whether it decoded anything**, so assert that it decoded — a
nonzero instruction count in the region, or no `<unknown>` — before counting
mnemonics. Where no disassembler exists, a behavioural probe with a negative
control is the better instrument anyway, which is how the xtensa row above was
taken.
