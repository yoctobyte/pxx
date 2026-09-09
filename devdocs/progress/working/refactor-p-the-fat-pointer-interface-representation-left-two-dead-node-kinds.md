---
slug: refactor-p-the-fat-pointer-interface-representation-left-two-dead-node-kinds
track: P
prio: 25
type: refactor
blocked-by: []
status: working
owner: frankH
found-by: frankD
created: 2026-09-09
summary: "An interface value used to be a 16-byte fat pointer {IMT, instance} and is now ONE WORD -- the instance pointer, with the IMT recovered per call from the instance's RTTI (PXXIntfIMTOf). Measured 2026-09-09: SizeOf(IIntf) = 8, a record of two is 16, an array of three is 24, and fpc 3.2.2 agrees on all three. The move left residue: `AN_INTF_FROM_CLASS` has ZERO references outside defs.inc, `IR_IMTADDR` is never created (four backend encoder arms plus an IRVerify arm for a node nothing emits), and about a dozen ir.inc lowering comments still narrate the fat pointer. Both constants are now marked dead in defs.inc with the census that would retire them; REMOVING them is node numbering, which CLAUDE.md says to coordinate by message rather than land alone, which is why this is a ticket and not a commit."
---

# Residue of the fat-pointer interface representation

## What is dead, and the census that says so

    grep -rn AN_INTF_FROM_CLASS compiler/ | grep -v defs.inc   -> 0 lines
    grep -rn 'IRAppend(IR_IMTADDR' compiler/                   -> 0 lines

`AN_INTF_FROM_CLASS` (defs.inc) is an AST kind nothing allocates. `IR_IMTADDR`
is an IR node nothing appends, and it still has encoder arms in
`ir_codegen.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc` and
`ir_codegen386.inc`, plus an `IRVerify` arm. Five arms for a node that cannot
occur.

`AN_INTF_CALL` is NOT in this set — 39 references, live, and
`pasparser_stmt.inc` states the current mechanism beside it ("recovers the IMT
per call via PXXIntfIMTOf").

## Why it is a ticket and not a commit

Removing an AST or IR node kind is **node numbering in `defs.inc`**, the one
thing CLAUDE.md says to coordinate by message. Both constants have therefore
been left in place and *marked* dead, each carrying the census command that
would retire it. Deleting them, and the five backend arms with them, needs the
message and cross-target gating that a four-backend edit implies.

## The comment drift, which is the expensive half

About a dozen comments in `ir.inc`'s lowering still describe the old
representation in live code:

- `build the CORBA fat pointer {IMT, instance} into the LHS`
- `interface := interface falls through to the 16-byte record copy below`
- `the address of its fat-pointer temp`
- `interface := nil — zero the whole fat pointer {nil, nil}`

They are describing code that moves one word. **This is not cosmetic — one of
these comments has already been read as a specification and cost a ticket.**
`bug-p-a-variant-cannot-hold-an-interface` was filed at prio 40 on
`pxx spells it tyRecord (a 16-byte fat pointer {IMT, instance})` taken from
`UClsIsInterface`'s own comment, and its design section prescribes widening the
variant payload from 8 bytes to 16 — work that is not needed, against a
representation that had already moved. It sat unclaimed from 2026-08-26 to
2026-09-09 with that blocker at the top of it.

Each of these needs its own path READ before rewriting, which is why they were
not corrected alongside the defs.inc ones: a comment rewritten from a
neighbour's measurement is exactly how this drift started. `defs.inc`'s
`UClsIsInterface` and `IMTClass` notes are corrected and say precisely what was
measured and what was merely read off a sibling.

## The measurement that settles any future version of this

    writeln(SizeOf(IIntf));   { 8, in pxx and in fpc 3.2.2 }
