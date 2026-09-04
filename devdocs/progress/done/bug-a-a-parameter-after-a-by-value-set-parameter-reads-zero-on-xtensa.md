---
slug: bug-a-a-parameter-after-a-by-value-set-parameter-reads-zero-on-xtensa
track: A
prio: 55
type: bug
status: done
blocked-by: []
owner: frankA
created: 2026-09-04
found-by: frankA (test_cross_byvalue_aggregate_params, wasm32 by-value work)
summary: "FIXED. The reported symptom was the SMALL half. On xtensa the callee spill (ir_codegen.inc EmitParamSpillsForTarget, TARGET_XTENSA arm) had no by-value SET arm: it stored word 0 into the parameter's 32-byte slot and advanced its word counter by ONE instead of eight. So (a) every parameter after the set read 0 -- the loud symptom this ticket was filed for -- and (b) THE SET ITSELF LOST EVERYTHING ABOVE BIT 31 while still answering correctly for every member under 32, because word 0 is the word that arrives. Measured against pin v403: [1,2,40,100,200,255] came back as 26 spurious members read out of live frame bytes. A [1,2] probe passes on the broken compiler, which is why the mask half went unreported. Fixed by adding the set arm and deriving the word count as TypeSlotSize(tySet) div 4 on BOTH sides."
---

# A parameter after a by-value set parameter reads zero on xtensa

## Reduced

Compared against the x86-64 build of the same source, xtensa built with
`--platform=posix --xtensa-soft-mulhigh`:

```pascal
type TS = set of 0..255;
procedure F(s: TS; x: Integer);
begin writeln(1 in s, ' ', x); end;
...
s := [1,2]; F(s, 30);
```

```
  xtensa   TRUE 0        <- x is lost
  x86-64   TRUE 30
```

The variations, all measured in one run:

| signature | xtensa |
| --- | --- |
| `F(s: TS; x: Integer)` | **`TRUE 0`** — wrong |
| `F(s: TS; x1, x2: Integer)` | **`TRUE 0 0`** — both lost |
| `F(x: Integer; s: TS)` | correct |
| `F(r: TPlain; x: Integer)` (8-byte record) | correct |
| `F(s: TS)` alone, copied to a global | correct |

So the SET's own 32 bytes arrive intact and everything after it does not. That
is a word-count disagreement about the set's slot between the caller's argument
push and the callee's parameter walk, not a value bug in either.

## Why nothing caught it

`ABIParamSlotHoldsValueAddr` puts x86-64, aarch64 and arm32 on the by-ADDRESS
row, so on those three a set param is one word and a trailing parameter cannot
be displaced. Only i386, riscv32 and xtensa pass the 32 bytes, and of those only
xtensa is wrong — which is the shape CLAUDE.md's "nothing observably differs is
a claim about ONE target" section is about, one row further out: here three
targets agree with each other and with the oracle, and the fourth does not.

## Where to look

`compiler/ir_codegen_xtensa.inc`'s parameter word walk, against
`compiler/ir_codegen.inc:1770`'s (the i386/shared one), which counts a by-value
set as `TypeSlotSize(tySet)` — 32 bytes, eight words — in the same loop that
counts a by-value record by `RecSize` and an Int64 as two. The likely defect is
xtensa counting the set as one word on one side of the call and eight on the
other.

## The test

`test/test_cross_byvalue_aggregate_params.pas` contains the row that found this
(`Mixed`, a by-value record and a by-value set among scalars, `x3` printed
after both). It is wired on i386, aarch64, arm32, riscv32 and wasm32 and
DELIBERATELY NOT on xtensa; the Makefile's xtensa recipe carries the exclusion
and this slug. Wiring it green would mean deleting the row that found the bug.
Un-exclude when this closes.


## Log

- 2026-09-04 - filed, commit e3919c0cb (the wasm32 by-value work whose new
  test found this; that commit also excluded the file from xtensa).
- 2026-09-04 - resolved, commit 724e04ea6. The exclusion is removed there and
  the file is wired on all six cross targets.

## RESOLVED 2026-09-04 (frankA)

Fixed in the same session that filed it, one commit later, because the reduction
kept getting worse as I looked at it.

**The filed symptom was the one that shows.** `F(s: TS; x: Integer)` giving
x = 0 is loud and obvious. Under it was the quiet one: the set parameter itself
carried only its first four bytes.

```
  s := [1, 2, 40, 100, 200, 255];  F(s);   { enumerate members }

  x86-64 / i386 / riscv32 / arm32 / aarch64 / wasm32   1 2 40 100 200 255 | count=6
  xtensa (pre-fix)                                     1 2                | count=2
  xtensa (pin v403, through the wired test)            1 2 64 128 160 192 193 194
                                                       195 198 200 ... | count=26
```

The `count=26` reading is the honest one: the untouched 28 bytes of the slot are
not zeroes, they are live frame data, so the parameter answers with whatever the
frame last held. The `count=2` reading came from a different frame state in a
smaller program. **Both are the same defect and neither is reproducible as a
constant** — which is the argument for asserting the whole enumeration rather
than a member count.

**A `[1,2]` probe passes on the broken compiler**, and `[1,2]` is what one
writes. Word 0 is the word that does arrive, and for a set with no high members
the missing words read as "not a member", which is the correct answer. The
guard has to put a member in every 32-bit word of the mask, including the top
bit, or it cannot fail.

### The fix

`compiler/ir_codegen.inc`, `EmitParamSpillsForTarget`, TARGET_XTENSA arm: a
`tySet` branch that copies all eight words (register or overflow-stack source
per word, exactly as the neighbouring 64-bit arm does) and advances `pw` by
eight. No even-word alignment skip, matching the caller, which does not emit
one either — the convention is internal, so the two sides must agree with each
other rather than with gcc.

**The word count is now `TypeSlotSize(tySet) div 4` on both sides**, where the
caller had a literal `for j := 0 to 7`. Two literals in two files is how the
sides stop agreeing, and arm32/riscv32 already record what a two-of-three state
costs for the 5-8 byte record: fixing the count without the slot turns data loss
into active corruption.

### Guard

`test/test_cross_byvalue_aggregate_params.pas`, wired on all six cross targets
(the xtensa exclusion this ticket created is removed in the same commit). Its
`ByValSetWide` row enumerates every member of `[1,2,40,100,200,255]`, and
`Mixed` now carries a high member too so the trailing-parameter row and the
mask row fail independently.
