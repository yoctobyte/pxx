---
slug: bug-n-pyparser-property-accessor-sites-do-not-know-an-interface-receiver
track: N
prio: 30
type: bug
status: backlog
owner:
blocked-by: []
summary: "`pyparser.inc` has ~9 hand-written copies of the property-accessor call decision, and each knows exactly two answers (AN_VIRTUAL_CALL / AN_CALL, Self at argument 0). The choice is three-way: an interface receiver needs AN_INTF_CALL, slot in ASTSOffset, Self from the fat pointer. The Pascal-side twins had the identical defect and were fixed by extracting one MakeAccessorCall (0f0fd6642); pyparser.inc was deliberately NOT touched because it is Track N's file and N is parked. NOT KNOWN TO BE REACHABLE from NilPy today -- this is the sibling half of a fixed double case, filed so it is not rediscovered, not a measured failure."
---

# `pyparser.inc`'s property-accessor sites have the two-answer form

## What this is, and what it is not

**This is a grep result with a known-bad shape, not a reproduced failure.** The
honest statement is: the Pascal side of this double case was measured, diagnosed
and fixed; the NilPy side has the same code and was left alone; nobody has
checked whether NilPy can put an interface on the receiving end of a property
access. File-and-move-on is the right size for it. Do not rank it as a bug in
NilPy until someone produces a `.npy` that reaches it.

It is filed at all because `normalise-dont-special-case.md` says to grep for the
sibling before closing a double case, and this is what that grep found.

## The shape

Every one of these builds the accessor call by hand and offers two dispatches:

```
pyparser.inc:38362  38423  39561  39645  40430  40525  41516  41546  41585  41645  43072
```

```pascal
if UMthVirSlot[mmi] >= 0 then begin call := AllocNode(AN_VIRTUAL_CALL); ASTRight[call] := UMthVirSlot[mmi]; end
else call := AllocNode(AN_CALL);
selfArg := AllocNode(AN_ARG); ASTLeft[selfArg] := recv;   { Self at argument 0 }
```

An interface receiver needs the third: `AN_INTF_CALL`, the IMT slot in
`ASTSOffset` rather than `ASTRight`, and **no Self in the argument chain** —
the callee takes it from the fat pointer's instance word. Getting that wrong
reads a class VMT off an interface value: a wrong pointer, then a crash, which
is what it did on the Pascal side.

## The fix already exists and is language-neutral

`MakeAccessorCall(mci, mmi, mpi, recvNode, firstArg)` and `AccessorArgChain` in
`compiler/pasparser_call.inc` (landed `0f0fd6642`). They touch no Pascal-specific
state — `UClsIsInterface`, `UMthVirSlot`, `Procs`, `AllocNode` — so calling them
from `pyparser.inc` is legitimate under
`the-substrate-is-ast-and-ir-not-the-parser.md`: this is AST construction, the
shared half, not lexing or grammar.

**But that is Track N's call, not Track P's**, which is the whole reason this is
a ticket rather than a commit. If N would rather have its own copy, that is a
defensible reading of "duplicate the parser per language" — the point is that the
decision gets made by the lane that owns the file.

## Provenance

Found while fixing [[bug-p-a-property-in-an-interface-declaration-is-rejected]],
where the identical eleven-copy shape on the Pascal side made a property on an
interface segfault. Not touched here because a cross-lane edit into a parked lane
is the worst version of "shared internals are fine to edit": nobody is there to
say whether it broke something.
