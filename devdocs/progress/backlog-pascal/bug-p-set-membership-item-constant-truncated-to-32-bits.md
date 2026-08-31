---
slug: bug-p-set-membership-item-constant-truncated-to-32-bits
title: "A set-membership item constant is truncated to 32 bits, silently, on every target"
track: P
type: bug
prio: 25
status: backlog
found: 2026-08-28
found-by: frankwasm (measured on five targets while implementing the wasm32 `in` arm)
---

> **DANGLING SHAS BY DESIGN.** The commit shas in this ticket live on branch
> **`wasm`**, not on `origin/master` — it was filed from the wasm lane's
> standalone checkout, which pushes to its own branch. `progress.sh check`
> flags them `SIDE-BRANCH-SHA` and that is correct rather than a defect: the
> measurement was taken where the work is. **Branch permission is not merge
> permission** — nothing on `origin/wasm` is pre-approved for master.
> Twelve-hex values like `2e68d018ccac` are **binary sha256** prefixes of
> `compiler/pascal26`, not commits at all, and will not resolve as objects.
> — frankwasm, 2026-08-30

## The fact

```pascal
var q: Int64;
q := 1;
WriteLn(q in [4294967297]);   { 2^32+1 — answers TRUE }
```

`1 in [4294967297]` is **TRUE** on x86-64, aarch64, arm32, i386 and wasm32. No
warning, no error. The item's low 32 bits are `1`, and that is what is compared.

The upper bound of a range goes the same way — `4294967296 in [4294967296..4294967300]`
is **FALSE** where it should be TRUE, because both bounds truncate to 0..4.

## Root cause — one `var` line, between two 64-bit endpoints

`compiler/pasparser_lval.inc:3057`, in `ParseSetMembershipAST`:

```pascal
var node, argNode, lastArg, loVal, hiVal, itemNode: Integer;
                              ^^^^^  ^^^^^
```

with, on either side of it:

```pascal
function ParseSetConst: Int64;            { pasparser_name.inc:456 }
ASTIVal : array of Int64;                 { defs.inc:3952 }
```

`loVal := ParseSetConst` narrows Int64 → Integer, and `ASTIVal[itemNode] := loVal`
widens it back. A 32-bit funnel between a 64-bit source and a 64-bit sink.

Not a set-range limit: `q in [300]` and `q in [70000]` are both correct, so the
boundary is exactly 32 bits and exactly this assignment.

## The sibling arm is also wrong, by what looks like a different mechanism

`ParseSetMembershipAST` has two paths, chosen by `SetLiteralHasRuntimeElement`.
The constant path is the one above. The runtime path (`ParseSetElementAST` →
`ParseSetLiteralAST`) assigns `CurTok.IVal` straight into `ASTIVal` with no
`Integer` stop — so it does **not** have this funnel, yet:

```pascal
q := 1; r := 9;
WriteLn(q in [4294967297, 5]);   { const path   — TRUE, wrong }
WriteLn(q in [4294967297, r]);   { runtime path — TRUE, wrong }
```

Measured, not diagnosed. The runtime path builds a 256-bit mask, so a value
outside 0..255 plausibly fails there for its own reason. **Whoever fixes the
funnel should check the mask path separately rather than assume one fix covers
both** — this is the double-case shape `normalise-dont-special-case.md` warns
about, and here both arms are broken, which is why neither one going green is
evidence about the other.

## The fork this needs decided

Two defensible fixes, and they are not the same:

1. **Widen** `loVal, hiVal` to `Int64`. One line. Consistent with `in` already
   accepting 300 and 70000 — the 32-bit stop is an accident, not a boundary.
2. **Reject** an item outside the element type's range at compile time. FPC would
   not compile `[4294967297]` at all; our `in` is a general "value in constant
   list" and deliberately laxer.

**Recommendation: (1).** Per `CLAUDE.md`'s compat table, "we accept a form FPC
rejects" is not a defect, so (2) is not required for parity; and the value that
makes the current behaviour a bug is the *silent wrong answer*, which (1) removes
without narrowing the dialect. (2) can follow later behind a strict flag if
anyone wants it.

Either way the current behaviour is wrong: answering TRUE is not one of the two
defensible outcomes.

## Reachability — read this before ranking it up

Real Pascal sets are 0..255. Code with a set item at or above 2^31 is close to
nonexistent, which is why prio is 25 and not higher despite being a silent wrong
answer on the default target. It is filed because it is silent, cheap, and
line-precise — not because it is blocking anything.

## Repro

```
printf 'program t;\nvar q: Int64;\nbegin q := 1; WriteLn(q in [4294967297]); end.\n' > /tmp/t.pas
./compiler/pascal26 /tmp/t.pas /tmp/t && /tmp/t     # TRUE; should be FALSE
```

Measured at branch `wasm` sha 954b56b53, compiler 2e68d018ccac; x86-64 and i386
run natively, arm32/aarch64 under `qemu-arm`/`qemu-aarch64`, wasm32 under node.
`riscv32` and `xtensa` refuse `in` outright and are unaffected.

## A note for whoever writes the test

A wasm-vs-native differential test **cannot catch this one**, because the defect
is upstream of every backend and both sides of the diff are wrong identically.
It needs an absolute expectation.
