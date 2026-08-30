---
slug: bug-a-riscv32-cannot-reach-a-far-call-so-the-compiler-will-not-link
track: A
prio: 55
type: bug
status: backlog
found: 2026-08-30
found-by: frankS
summary: "`pascal26 --target=riscv32 compiler/compiler.pas` fails with `jal displacement 2197196 is outside the encodable range -1048576..1048574`. JAL reaches +/-1 MB; the compiler is the biggest program we have and is the first to exceed it. Every other blocker on that target is now cleared -- riscv32 was one of the four fixed by the LoadFile normalisation and this is what it hit next."
---

# riscv32 cannot reach a far call, so the compiler will not link

## Measured

```
$ compiler/pascal26 --target=riscv32 compiler/compiler.pas /tmp/out
pascal26:8307: error: target riscv32: jal displacement 2197196 is outside the
  encodable range -1048576..1048574; the code is too large for this branch form
```

2.20 MB against JAL's ±1 MB. Ordinary programs cross-build and run on riscv32
fine; it is specifically the compiler's size that exceeds the form.

## The shape of the fix already exists in-tree

xtensa hit the identical problem and solved it: `EmitXtensaLongCall`
(`symtab.inc`) materialises the target address into a register and does an
indirect call, and `EmitXtensaCallToCode` picks the short or long form by asking
`XtensaCallReaches`. riscv32 needs the same pair — `auipc`+`jalr` is the natural
long form there, and it is a two-instruction sequence with ±2 GB reach.

The reach test must be the thing that chooses, not a heuristic about program
size: a build that is *nearly* over the line must still emit the cheap form for
the calls that fit.

## Sibling

[[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]]
is the same family and is about xtensa's remaining forward-reference case. This
one is riscv32 and is about JAL specifically.

## Gate

`make compiler/pascal26`, then `pascal26 --target=riscv32 compiler/compiler.pas`
must produce an artifact; plus the riscv32 cross battery, since every call in it
now goes through whichever form the new chooser picks.
