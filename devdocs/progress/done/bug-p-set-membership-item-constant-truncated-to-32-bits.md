---
slug: bug-p-set-membership-item-constant-truncated-to-32-bits
title: "A set-membership item constant is truncated to 32 bits, silently, on every target"
track: P
type: bug
prio: 25
status: done
found: 2026-08-28
found-by: frankwasm (measured on five targets while implementing the wasm32 `in` arm)
summary: "FIXED on the 64-bit targets in 831919a7d. `loVal, hiVal` in ParseSetMembershipAST were Integer between an Int64 source and an Int64 sink, AND every backend re-narrowed with an Integer() cast, so both halves had to be widened; x86-64 additionally could not encode the immediate (`cmp rcx, imm32` sign-extends), which is why the boundary sat at exactly 2^31. Recommendation (1), widen, was taken. Two residuals split out and owned: the 32-bit backends and the runtime/mask arm."
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


---

## Resolved on the 64-bit targets — 2026-09-05, frankO, `831919a7d`

**Recommendation (1) was taken**, and the diagnosis above was right about the
`var` line and incomplete about the rest. Three things worth carrying:

**There were TWO narrowings, not one.** Widening `loVal, hiVal` alone does not
move a single row. Every backend re-narrowed with an explicit
`Integer(IRIVal[...])` in its SPECIAL_IN walk, so the value was 64-bit at every
point it was *stored* and 32-bit at both points it was *passed*. Run as a
control rather than argued: with the backend widened and the parser left
narrow, rows A/B/C are still wrong.

**x86-64 needed more than deleting a cast.** `cmp rcx, imm32` (`48 81 F9`)
sign-extends a 32-bit immediate, so the instruction cannot hold 2^31 at all —
the measured boundary was exactly 2147483647 in / 2147483648 out, which is the
immediate's range and not a property of sets. New `CmpRcxImm` in `emit.inc`
keeps the imm32 form and otherwise does `push rdx / movabs rdx / cmp rcx,rdx /
pop rdx`; push-pop because POP leaves EFLAGS alone, so it needs no liveness
argument about the surrounding expression.

**FPC is not the oracle here, and checking it changed the framing.** fpc 3.2.2
answers `1 in [4294967297]` **TRUE** and `300 in [300]` **FALSE** — its set is
a 0..255 byte set. So the "correct" column had to come from what the source
meant, not from parity; this ticket's own note that `q in [300]` and
`q in [70000]` already worked is what establishes pxx's domain is wider by
design.

### One claim in the body above is now false

> `riscv32` and `xtensa` refuse `in` outright and are unaffected.

riscv32 does **not** refuse it — it compiles and runs `x in [consts]` under
`qemu-riscv32` and fails the same rows as i386 and arm32. xtensa cannot be run
on this host and remains unmeasured. Left in place above rather than edited,
since below-the-summary history is append-only.

### Residuals, both owned

- `backlog-core/bug-a-set-membership-32-bit-backends-truncate-the-set-constant`
  — i386/arm32/riscv32 all print `SETIN64 FAILED 5`, identical row for row.
  Different mechanism: they compare the low word plus a fits-in-int32 flag,
  the shape `done/bug-a-set-membership-truncates-the-test-value-on-32-bit-backends`
  installed for the test VALUE.
- `backlog-pascal/bug-p-the-two-arms-of-in-disagree-about-their-own-domain-silently`
  — the runtime/mask arm this ticket asked to be checked separately. It was
  right that one fix would not cover both. The finding is not the 2^32 rows
  (FPC diagnoses those as out-of-domain, so matching its value is not a goal)
  but `q in [r]` with `r = 300` answering FALSE while `q in [300]` answers TRUE.

Regression test `test/test_set_in_64bit_const.pas`, wired at `Makefile:5110`.
Positive control asserted: against the pre-fix pin it reports `SETIN64 FAILED 5`.

## Log
- 2026-09-05 — resolved, commit 831919a7d.

### Blast radius, checked after the fact rather than assumed

`cmp rcx, imm32` sign-extending is a property of x86-64 comparisons, not of
sets, so the reasonable follow-up question is whether every wide-constant
comparison was wrong and this ticket undersold itself. **It did not.** A plain
`if q = 4294967297`, the five other relational operators, and `case q of
4294967297` are all correct at `831919a7d` AND against the pre-fix pin — the
general lowering already materialises a wide immediate into a register. Only
the hand-emitted SPECIAL_IN walk emitted a bare `48 81 F9` and so inherited the
encoding limit. Bounding this cost one probe and is recorded because the
negative result is what keeps the residual ticket honestly sized.

Cross measurements in this ticket and its residual were taken under
`qemu 10.2.1`, host kernel `7.0.0-30`. Not hardware.
