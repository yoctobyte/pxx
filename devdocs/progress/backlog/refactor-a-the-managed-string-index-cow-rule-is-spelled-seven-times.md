---
track: A
prio: 45
type: refactor
blocked-by: []
summary: "The 'is this a managed string being indexed, so an lvalue write needs copy-on-write' rule is implemented independently in all SEVEN backends. Six spell the stride test `(elemSize = 1)`; aarch64 spells it `(Integer(IRIVal[node]) = 1)` because it never hoists the local — so a grep for the common spelling returns six files and silently omits the seventh. Changing the rule means editing seven files atomically, which is exactly what feature-unicodestring-model step 4 had to do."
status: new
owner: ""
---

# The managed-string index COW rule is spelled seven times, one of them ungreppable

- **Type:** refactor — **Track A** (the backends).
- **Found:** 2026-08-30 by frankwasm, while applying `feature-unicodestring-model`
  step 4, which had to widen this exact predicate in every backend at once
  (`e2dba4293`).
- Sibling of [[refactor-p-the-char-array-is-not-a-string-rule-is-spelled-five-times]].
  That one is five spellings in one file; this is seven spellings in seven files.

## The measurement — and the denominator is the point

**Seven backends exist, therefore there are seven sites.** That is the count to
check against, and it comes from `ls compiler/ir_codegen*.inc`, which is a
directory listing — a source independent of any content search. Stated this way
on purpose: the useful number is the *denominator*, not the list below it.

    ir_codegen.inc:6053           (elemSize = 1)                baseAddr, not left
    ir_codegen_aarch64.inc:3420   (Integer(IRIVal[node]) = 1)   the ungreppable one
    ir_codegen_arm32.inc:3295     (elemSize = 1)
    ir_codegen386.inc:3902        (elemSize = 1)
    ir_codegen_riscv32.inc:1673   (elemSize = 1)
    ir_codegen_wasm32.inc:1133    (elemSize = 1)
    ir_codegen_xtensa.inc:1677    (elemSize = 1)

All seven answer the same question — *is this base a managed string being
indexed, so that an lvalue write must clone-if-shared?* — with the same two
conjuncts: `IRTk[base] = Ord(tyAnsiString)`, plus a stride test separating
indexing INTO a string from indexing an array whose ELEMENTS are strings (stride
8, where `IRTk` is `tyAnsiString` for the element's sake, not the base's).

**`grep 'elemSize = 1' compiler/ir_codegen*.inc` returns SIX.** aarch64 never
hoists `Integer(IRIVal[node])` into an `elemSize` local, so its otherwise
identical line does not match. The census instrument shares the defect it is
censusing: the rule is spelled inconsistently, and the inconsistency is what
hides a copy of it.

## Why it is worth consolidating

- **Every change to the rule is a seven-file atomic commit.** Step 4 widened the
  stride test to admit UTF-16 (stride 2) and had to hold seven files at once,
  across three other agents' lanes, coordinated through a scheduled window. One
  predicate would have made it a one-line change in a shared file.
- **A partial application is undetectable in exactly the case that matters.**
  Step 4's own ordering constraint spells this out: until something constructs a
  wide string, an unwidened backend is inert, and it becomes live only when the
  enabling switch is thrown — at which point it presents as alias corruption
  with no recent cause. Seven copies is seven chances to miss one.
- `devdocs/dev/root-cause-over-microfix.md` sets the line at *"two is a smell,
  three is a design flaw."* This is seven.

## What to do

Hoist the predicate to one function beside the other shared backend helpers —
something of the shape `IRIndexBaseIsManagedStr(node, base): Boolean` — and have
all seven call it. Note it is NOT quite a pure textual duplicate:

- x86-64 reads `IRTk[baseAddr]`, the others read `IRTk[left]`; same node, local
  name differs.
- x86-64 assigns into an `isAnsiStr` flag consumed a few lines later; the others
  test inline in an `if/else` chain.
- aarch64 has no `elemSize` local at all and reads `Integer(IRIVal[node])`
  directly — the helper should take the node and derive the stride itself, which
  removes that difference at the source rather than papering over it.

So the consolidation must read the sites, not sed them. Budget accordingly, and
per `normalise-dont-special-case` the win is measured in **cases deleted**.

## Gate

`make compiler/pascal26` + the copy-on-write corpus from step 4: aliasing
(`b := a; a[1] := 'J'` must leave `b` intact) through a plain variable, a record
field and an array element, plus the read path — output identical to `pinned`
before and after.
