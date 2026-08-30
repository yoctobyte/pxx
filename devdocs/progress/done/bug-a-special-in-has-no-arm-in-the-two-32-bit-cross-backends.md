---
slug: bug-a-special-in-has-no-arm-in-the-two-32-bit-cross-backends
track: A+S
prio: 45
type: bug
blocked-by: []
status: done
summary: "`x in [items]` reaches codegen as TWO different shapes: a set literal with any runtime element becomes an ordinary AN_BINOP tkIn, while an all-constant literal never becomes a set at all — the parser emits an AN_CALL with -SPECIAL_IN. ir_codegen.inc, aarch64, arm32 and i386 carry the second arm; riscv32 and xtensa did not, so two programs failed to COMPILE on both. Found by classifying the xtensa tail, and it is the sibling of an arm I added myself four hours earlier and did not grep for."
owner: frankS
---

# SPECIAL_IN has no arm in the two 32-bit cross backends

## The double case

`ParseSetMembershipAST` (`pasparser_lval.inc`) forks:

- **any runtime element** → `ParseSetLiteralAST` builds the mask at runtime and
  the test becomes an ordinary `AN_BINOP` with `tkIn`;
- **every element constant** → no set is built at all. The node is an `AN_CALL`
  with `ASTIVal = -SPECIAL_IN`, and the backend compares inline.

Two shapes for one construct, which is what
[[devdocs/dev/normalise-dont-special-case]] is about — and the parser's own
comment records that these two paths had **already diverged once**:
`writeln(e in [a,b])` printed `1` instead of `TRUE`, because only the binop arm
was typed `tyBoolean`. That fix typed the node. Nobody checked whether every
backend implemented both arms.

`grep SPECIAL_IN compiler/`: `ir_codegen.inc`, `ir_codegen_aarch64.inc`,
`ir_codegen_arm32.inc`, `ir_codegen386.inc`. Not riscv32. Not xtensa.

## How it was found, and the part I have to own

I added the `tkIn` arm to `ir_codegen_xtensa.inc` earlier the same session,
measured it green against the oracle, and closed the ticket. **`in` has two
shapes and I fixed one.** The rule that says to look for the other is the rule
this repo wrote down, in a lane that had spent the night finding exactly this
shape in other people's code. Nothing failed; the ticket closed green; the
sibling sat two programs away.

What surfaced it was not a hunch but **classifying the tail instead of guessing
at it** — partitioning all 23 remaining xtensa compile failures into seven named
categories, which is what made a "builtin with no arm" bucket exist at all.
Builtin `-999` is `SPECIAL_IN` (`defs.inc`).

## Both backends, one change

riscv32 was fixed in the same commit rather than filed. Fixing one arm of a
double case and filing the other **is the same defect one level up**: it leaves
riscv32 as the next lane's surprise. A repair for a fixed-on-one-arm-only bug
that is itself applied to one arm is not a partial fix.

`ir_codegen_riscv32.inc` is Track A's file; scope granted for this arm only,
with the collision check recorded (`grant-ir-codegen-riscv32-to-track-s-for-the-special-in-arm`).

Same rule, each backend's own idiom — which is what normalising across targets
should look like:

| backend | how the membership accumulates |
| --- | --- |
| arm32 (model) | conditional execution — `moveq r4, #1` |
| **riscv32** (new) | **branchless**: `slt` / `sltiu` / `xori`, no labels, no patching |
| **xtensa** (new) | branches over a `movi` — no conditional execution, same reason its `tkIn` arm had to branch for want of `sltiu` |

Xtensa constants go through `EmitLoadConstXtensa`, never a bare `movi`:
`xtensa_movi` masks to 12 bits **with no range check**, so a set element above
2047 would silently encode as something else. That is why each xtensa item is
its own `EmitAsmXtensa` block — the literal-pool fallback can emit a jump, and
labels are scoped per block, so nothing branches across one. Registers avoid a7
(frame pointer under the windowed ABI) and a15 (frame pointer under Call0).

Both arms also refuse a non-constant element rather than reading `IRIVal` off
whatever node is there. The parser cannot deliver one today; arm32 would produce
a wrong value if it ever did.

## Measured — two independent sweeps, both against a rebuilt baseline

129 sources, each target against the x86-64 oracle:

```
xtensa    MATCH  97 -> 99    CFAIL 23 -> 21    regressions: NONE
riscv32   MATCH 107 -> 109   CFAIL 18 -> 16    regressions: NONE
```

Exactly two rows moved on each, both off CFAIL: `test_cross_in_operator` and
`test_cross_string_cow`. The riscv32 baseline was produced by stashing the
change and **rebuilding the compiler at HEAD** (`a60f92ba830a`), not by reusing
an older binary — the same discipline that caught a confounded measurement
earlier in this session.

Four rows wired: two into `test-xtensa` (now 100), two into `test-riscv32`,
where they **replace explicit `# SKIP … backend feature gap` comments**. Those
comments named the right cause and nobody had priced it.

## A note for whoever reads riscv32's diagnostic next

riscv32's message for a missing builtin arm reads *"standard builtin calls not
supported in bare-metal stage 1"* — and it is reached under an ordinary hosted
cross compile where there is no bare-metal stage. It **does** append
`(builtin id 999)`, so the subject is named; it is the sentence that is stale
and sends the reader to a profile question that is not the problem. Same defect
class as the xtensa messages fixed earlier tonight
([[bug-a-iropname-has-no-entry-for-seven-ir-ops-so-a-missing-arm-reports-unknown]]).
Not fixed here — chasing it would widen an A-file grant scoped to one arm.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
