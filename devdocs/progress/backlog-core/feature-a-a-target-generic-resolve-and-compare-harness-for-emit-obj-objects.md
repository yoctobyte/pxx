---
slug: feature-a-a-target-generic-resolve-and-compare-harness-for-emit-obj-objects
title: "No pxx object outside x86-64/i386 has ever had its relocations RESOLVED: build a target-generic resolve-and-compare harness"
track: A
prio: 55
type: feature
status: open
created: 2026-09-22
found-by: frankb-8e
owner:
blocked-by: []
summary: "Every ESP object this tree emits -- riscv32 and xtensa, both with shipped writers -- is verified only by `readelf -r` assertions on relocation TYPE and SYMBOL, and NOTHING in the tree has ever linked or run one. Type-and-symbol cannot see a wrong addend, a misplaced bit-field inside an instruction's immediate, or an offset four bytes out, which is precisely the defect class an object writer produces. The instrument that closes it needs no linker and no new target support: pxx emits the same program as an EXECUTABLE (proven by running under qemu in the existing per-target tiers) and as an OBJECT, the harness applies the object's relocations at the executable's section addresses USING ITS OWN ARITHMETIC, and the resulting .text and .data must be byte-identical to the executable's. INDEPENDENCE IS THE WHOLE VALUE and is the easy thing to lose: if the harness applies relocations by calling back into pxx, or if the object writer records a value the executable writer already computed instead of an addend the harness must resolve, the comparison is a self-consistency check wearing the shape of a correctness check and it passes forever. Build it target-generic rather than aarch64-shaped -- xtensa and riscv32 inherit it for free and that is the axis the owner tests personally. Positive controls must perturb TYPE, ADDEND and OFFSET independently, and each must redden. Residual it cannot close: whether a real LINKER agrees with our relocation semantics (needs a cross-linker this box does not have), and any relocation on a path qemu never executes."
---

# Why this is not covered today

`test-emit-obj` asserts, for the ESP writers, rows of the shape

```
readelf -rW esprod_$t.o | grep -qE 'R_(RISCV|XTENSA)_32 +[0-9a-f]+ +\.rodata \+'
```

— relocation type, and the section or symbol it names. That is a real check and
it catches a whole class (the relocation missing, or aimed at the wrong
symbol). It is structurally unable to catch:

- a wrong **addend** — the type is right, the symbol is right, the resolved
  address is off by whatever the addend is wrong by;
- a value written into the **wrong bit-field** of an instruction — on aarch64 a
  `MOVW_UABS` immediate lives at bits 5..20 of the `movz`/`movk` word, so a
  correct value in the wrong place is a correct-looking relocation;
- an **offset** four bytes out, which relocates the neighbouring instruction.

All three produce an object that a linker accepts. **A successful link is a
default-shaped pass** in the same sense an empty-equals-empty comparison is: it
is what you get when the machinery did something plausible and something wrong.

# The instrument

1. Build program P as an executable for target T. This leg is already
   independently proven — the per-target tiers run these under qemu.
2. Build the same P with `--emit-obj` for target T.
3. Read the object's relocations (type, offset, symbol, addend) and its section
   contents.
4. **Apply them in the harness, with the harness's own arithmetic**, at the
   section addresses the executable used.
5. Assert `.text` and `.data` come out byte-identical to the executable's.

The oracle chain is **qemu proves the executable, the executable proves the
object.**

## The independence requirement, which is the whole value

frankuser's objection, 2026-09-22, and it is the one the three obvious positive
controls do not reach: perturbing type, addend and offset tests the HARNESS.
It does not test the case where **the executable path and the object path share
the code that computes a relocation's value** — then a bug in that shared
routine makes both sides wrong identically and the comparison passes.

Two ways to lose it, both easy:

- the harness applies relocations by calling back into pxx;
- the object writer emits, as an addend, a value the executable writer already
  computed, rather than one the harness must resolve from the symbol table.

Write the applier from the **psABI**, not from `elfwriter.inc`. If it turns out
the harness cannot do its own arithmetic without reusing a pxx routine, **that
is itself the finding** and belongs in this ticket before anything is built on
top of it.

## Two tiers of evidence, marked as such

Where an external oracle reaches, use it and say so. clang emits
`R_AARCH64_CALL26` for a direct call and can oracle that row; it emits
`adrp`/`add` where pxx emits `movz`/`movk`, so it cannot oracle
`MOVW_UABS_G0_NC`/`G1_NC` at all. The output should say which relocations have
an external oracle and which rest on resolve-and-compare, so a later reader
does not quote the weaker tier as the stronger.

# What it does NOT establish

- **That a real linker agrees with our relocation semantics.** That needs a
  cross-linker, and this box has none for aarch64, arm32 or riscv32 (GNU ld
  2.46 offers x86 emulations only; no lld; no cross-gcc). Measured 2026-09-22.
- **Any relocation on a path qemu never executes.** The first link of the chain
  is execution, so it is exactly as wide as the program's coverage. Prefer a
  probe program whose every relocated site is on the executed path, and say
  which sites are not.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]
