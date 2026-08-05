---
summary: "pxx gives dynamic arrays COPY-ON-WRITE on x86-64 by deliberate design; FPC/Delphi make them reference types where writes through one alias ARE visible through another. Both cannot be true. Which one is pxx's dialect?"
type: decide
track: U
prio: 65
---

# Dynamic arrays: copy-on-write (pxx today) or reference semantics (FPC)?

- **Type:** decide — Track U
- **Status:** backlog
- **Opened:** 2026-08-05
- **Raised by:** Track A, from
  `bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing`. Escalated
  rather than fixed because the codebase asserts the current behaviour as
  INTENDED, so "fix it to match FPC" would be overruling a design decision, not
  repairing a slip.

## The fork

Measured, `b := a` on a dynamic array then writing through each name:

| | after `b[0]:=77` | after `a[1]:=88` |
| --- | --- | --- |
| **FPC** | a[0]=77 (visible) | b[1]=88 (visible) |
| pxx i386 / arm32 / aarch64 / riscv32 | a[0]=77 | b[1]=88 |
| **pxx x86-64** | **a[0]=1** (invisible) | **b[1]=2** (invisible) |

So x86-64 copy-on-writes; every other target aliases; FPC aliases.

## Why this is a decision and not a bug report

The COW is **deliberate machinery**, not an accident:

- `IR_DYNUNIQUE` exists specifically to "load the data pointer on a read and
  clone-if-shared (copy-on-write) on a write, decided by `InLValueWrite`".
- `PXXDynArrayUnique` is its RTL half.
- `compiler/ir.inc` states the invariant outright: *"writing through one alias
  never mutates another at any depth."*

Meanwhile `ir_codegen_arm32.inc` says *"v1: no COW either way"* — so the cross
targets are not implementing a different design, they simply have not
implemented this one. The five-versus-one split is an implementation gap on top
of an intentional divergence, which is why it reads as a bug from either side.

## Options

1. **FPC parity — drop dynarray COW.** Dynamic arrays become plain reference
   types everywhere. Matches the oracle, matches five of six targets today,
   and matches what every Delphi/FPC programmer expects; a `Copy(a)` is how you
   ask for a copy. Cost: removes a real safety property, and any existing pxx
   code (or test) that leans on the copy breaks *silently*, in the direction
   that is hardest to notice. Blast radius unknown until measured.
2. **Keep COW and finish it** — implement `IR_DYNUNIQUE` on i386/arm32/aarch64/
   riscv32 so all six targets agree. Cost: four backends of work, and pxx is
   then permanently out of FPC parity on a core type, which every `compat`-tagged
   effort has to know about.
3. **Keep COW as x86-64-only** — i.e. today. Rejected as an option: the same
   program gives different answers per target, which is the one outcome nothing
   should choose.

## Recommendation

**Option 1.** `compat` is a stated goal for the Pascal frontend, dynamic arrays
are core language surface rather than a dialect nicety, and the cheapest signal
available says the ecosystem already assumes aliasing: five of six targets do it
and nothing has complained. Option 2 is defensible only if the COW property is
something pxx actively wants to sell, and if so it should be written down in the
language reference rather than living in an IR comment.

Whoever takes option 1 should measure the blast radius first: build the corpora
and `make test` with COW disabled and see what changes, before committing to it.

## Blocks

`bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing` — that ticket's
observation stands either way, but its FIX direction depends entirely on this.
Its regression test (`test/test_dynarray_whole_assign.pas`) was deliberately
written NOT to assert aliasing, so it stays valid whichever way this goes.
