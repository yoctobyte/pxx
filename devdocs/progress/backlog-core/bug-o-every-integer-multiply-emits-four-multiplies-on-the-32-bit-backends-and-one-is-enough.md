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
summary: "MECHANISM: integer binops are typed tyInt64 with tyInteger operands AND a tyInteger destination, so every 32-bit backend lowers `a * b` as a full 64x64 expansion -- low product, high product, and two cross products -- and then stores only the low word. On the 32-bit targets that is FOUR multiply instructions and two adds where ONE would do, at every declared width; on x86-64 a 64-bit imul is one instruction, so the cost is invisible on the primary target and paid only by i386, arm32, riscv32 and xtensa. Measured on riscv32 by counting multiplies in the executed trace: Integer*literal, Integer*Integer, Int64*Int64 and SmallInt*SmallInt all emit 4, against a 0-multiply negative control whose only change is `+` for `*`. THE FIX IS CONSUMER-AWARE NARROWING AT LOWERING TIME -- emit only the low multiply where the result is provably consumed at <=32 bits -- and NOT narrowing the binop's TYPE. The type is load-bearing and that half is CLOSED: ir_codegen.inc's EmitOvfCheckNarrowX64 documents that the wide evaluation is what makes the mathematically exact result available, which is what {$Q+} overflow detection is built on as a range test, so narrowing the type would silently remove overflow detection on every target to save instructions on four. THE CONDITION THAT RETIRES IT: an integer multiply whose result is consumed at 32 bits emits one multiply instruction on all four 32-bit backends, with the {$Q+} overflow rows still green and a row asserting the product's VALUE (a narrowing that computes the wrong product would pass an instruction count)."
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
