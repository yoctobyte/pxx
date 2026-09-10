---
slug: feature-p-unaligned-is-a-transparent-lvalue-not-a-function
title: "`Unaligned(x)` — FPC's alignment-relaxing passthrough, on both sides of `:=`"
track: P
prio: 40
type: feature
status: done
owner: "frankH"
found-by: frankH
created: 2026-09-10
tags: [fpc-corpus, intrinsics, lvalue]
blocked-by: []
summary: "DONE. `Unaligned(x)` IS `x`, on both sides of `:=`, landed as TWO parser arms -- the read half in pasparser_expr.inc and the write half in pasparser_stmt.inc. It was the first failure of 150 of FPC's 207 compiler units at dbb96cdb6. IT COULD NOT GO IN builtin.pas: 275 call sites in that corpus and several are ASSIGNMENT TARGETS (entfile.pas:2003, ogomf, owomflib), which a function result cannot be, while cclasses.pas -- the unit the 150 stop on -- only READS through it. So a builtin-shaped fix would have cleared all 150 and left three units failing on the identical spelling. THE FORK THIS TICKET OPENED FOR THE OWNER COLLAPSED ON MEASUREMENT and no decision was needed: IR_LOAD_MEM and IR_STORE_MEM carry no alignment at all, so `p^` is already one plain access on every target and identity adds no behaviour. The strict-alignment question is real, is about `p^` rather than this name, and was open before this arm existed."
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


## Resolved 2026-09-10, frankH

Landed as two parser arms, not a builtin.

| half | file | what needs it |
| --- | --- | --- |
| read | `pasparser_expr.inc`, the `name` dispatch beside `bitsizeof` | `cclasses.pas:1327`, and so the 150 units |
| write | `pasparser_stmt.inc`, the soft-intrinsic chain | `entfile.pas:2003`, `ogomf.pas`, `owomflib.pas` |

Both arms are guarded so a user routine or an in-scope symbol named
`unaligned` shadows the intrinsic — `SoftIntrinsicOpenSym` on the statement
side, `FindSym`/`FindProc` on the expression side. **fpc does the same**: it
compiles a program declaring `function unaligned(x: LongInt): LongInt` and
calls the user's. That row is not decoration — with the guard removed the
passthrough fires and the program prints 5 instead of 6, compiling clean.

### The fork this ticket opened is withdrawn, and the withdrawal is the finding

The original body asked the owner to choose between identity everywhere and
byte-wise access on strict-alignment targets. **That question should never have
been written.** `IR_LOAD_MEM` and `IR_STORE_MEM` carry no alignment flag, so a
dereference in this compiler is one plain access on every target already.
`Unaligned(p^)` meaning `p^` therefore adds no behaviour and removes no
guarantee — it states what every other dereference was doing.

Whether a strict-alignment target should split a possibly-unaligned access into
bytes is a real question. It is a question about `p^`, it was open before this
intrinsic existed, and this change does not touch it. Escalating it here would
have spent the owner's turn on a decision the code had already made — the exact
failure CLAUDE.md describes as "the worst question is one a MEASUREMENT would
have answered", and it took one grep of `ir.inc`.

### Controls, all three fired

Claims of the form "reverting X breaks this" are worth nothing unless run.

| control | result |
| --- | --- |
| revert the WRITE arm, keep the read arm | fixture fails to compile at line 61 |
| revert the READ arm, keep the write arm | fixture fails to compile at line 54 |
| remove both shadow guards | shadow fixture prints 5, wants 6 |

The first two matter because the two arms are separate code paths: neither
makes the other's rows pass, which is what the single fixture asserting both
would otherwise be assuming. That assumption is the mechanism recorded in
CLAUDE.md as [[a measurement can create the condition it is testing for]] —
established one commit earlier, on this ticket's own predecessor.

Tests: `test/test_p_unaligned_is_a_transparent_lvalue.pas` (6 rows, both
halves, every pointer offset one byte from the array base so the accesses are
genuinely unaligned) and
`test/test_p_a_user_routine_named_unaligned_shadows_the_intrinsic.pas` (its own
file, because the declaration shadows the whole program). Both byte-identical
to fpc 3.2.2 on the same source.
