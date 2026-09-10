---
slug: feature-p-unaligned-is-a-transparent-lvalue-not-a-function
title: "`Unaligned(x)` — FPC's alignment-relaxing passthrough, on both sides of `:=`"
track: P
prio: 40
type: feature
status: open
owner: ""
found-by: frankH
created: 2026-09-10
tags: [fpc-corpus, intrinsics, lvalue]
blocked-by: []
summary: "`undefined variable (unaligned)` is the first failure of 54 of FPC's 207 compiler units, measured at 0dfa0b298, and it is the wall immediately behind IndexQWord (dbb96cdb6). It cannot go in builtin.pas: 275 call sites in the corpus and some are ASSIGNMENT TARGETS (`unaligned(pqword(@b[2])^) := v`, entfile.pas:2003, plus ogomf/owomflib), which a function return cannot be. It is a parser passthrough — FPC's `in_unaligned_x`, compinnr.pas:77 — that yields its argument unchanged and only relaxes the alignment assumption. On x86-64 the identity lowering is exact; on a strict-alignment target it is NOT, and that is the part of this ticket that needs a decision rather than an implementation."
---

# `Unaligned(x)` is a passthrough, not a call

## Where it bites

`tools/fpc_compiler_corpus_probe.sh` at `0dfa0b298`: 54 of 207 units stop on
`pascal26:1327: error: undefined variable (unaligned)`. Line 1327 is
`cclasses.pas`, the MurmurHash3 body:

```pascal
h := RolDWord(h xor (RolDWord(unaligned(pUint32(p)^) * C1, 15) * C2), 13) * 5 + $e6546b64;
```

`cclasses` is a dependency of most of the compiler, so one call site accounts
for all 54. `RolDWord` already resolves; only `unaligned` does not.

## Why builtin.pas is the wrong place, and this is the whole finding

The Index/Compare family that landed at `dbb96cdb6` went into `builtin.pas`
because those are ordinary functions. **This one cannot.** 275 uses in the
corpus, and they appear on the LEFT of an assignment:

```pascal
unaligned(pqword(@floatx80_ba[2])^) := floatx80_e.low;    { entfile.pas:2003 }
unaligned(PUint32(@RawRecord.RawData[NextOfs])^) := NtoLE(uint32(ChunkStart));
                                                          { ogomf.pas:1391 }
```

A function's result is not assignable, so any implementation shaped like the
Index family compiles the rvalue half and rejects the lvalue half — and the
rvalue half is what `cclasses` uses, so **a builtin-shaped fix would clear all
54 units and leave `ogomf`, `owomflib` and `entfile` failing on a construct
that looks identical.** That is the shape worth naming here: the popular call
site and the hard call site are the same spelling.

FPC treats it as an intrinsic (`in_unaligned_x = 54`, `compinnr.pas:77`), which
is why it can sit on either side.

## What it means

`Unaligned(X)` IS `X`. It carries no value change at all — it tells the
compiler not to assume the access is aligned. So the parser change is to
recognise the name in a factor/lvalue position and return the parsed argument's
node unchanged.

## The part that is not an implementation detail

The identity lowering is only correct where the hardware permits an unaligned
access. x86-64 permits it, and it is the default target, so the corpus attempt
is served. It is NOT free everywhere: xtensa traps, riscv may, and this
compiler has both as cross targets. An identity lowering there produces a
program that compiles and faults at run time — the expensive failure shape,
not the cheap one.

Two honest options, and this ticket does not pick one:

1. Identity everywhere, and record under `known-incompat` that a strict-
   alignment target inherits the host's assumption. Cheap, correct for the
   umbrella, wrong for a real xtensa program that uses it.
2. Identity on the permissive targets, byte-wise assembly/disassembly on the
   strict ones. Correct, and it needs an lvalue path that can emit a
   read-modify-write rather than a single access.

Nothing in the FPC corpus attempt discriminates these — every unit of it is
compiled for x86-64. So do not let the corpus number rank this: the 54 is real
and it is entirely served by option 1.

Reached from [[umbrella-pxx-compiles-fpc-itself]]; the wall before it was
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
then `bitsizeof` then `PSizeUInt` then the Index/Compare family.
