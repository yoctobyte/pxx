---
prio: 35
track: P
summary: "`for x in F` where F is a function RETURNING A SET is refused with `for-in: not a generator, enum type, or iterable variable`; fpc 3.2.2 accepts it and prints `0 2`. NARROW AND MEASURED: the same loop over a DYNARRAY-returning function works, and so does `for m in F.s` where F returns a RECORD holding the set -- so this is not `for-in over a call` in general, it is the SET result specifically. Assigning to a temp first (`s := F; for m in s`) works and is the workaround. Found beside bug-p-a-set-parameter-loses-its-element-kind-so-for-in-refuses-it and deliberately NOT folded into it: that one was a missing symbol stamp on a parameter, this one never reaches the set path at all (different diagnostic, from the container dispatch rather than from BuildForInSetLoop), so a fix for one is no evidence about the other."
owner: frankB
---

# `for x in F` is refused when F returns a set

- **Type:** bug — Track P (Pascal frontend)
- **Status:** done
- **Found:** 2026-09-05 (frankB), while fixing the set-PARAMETER stamp

## Repro

```pascal
program f1;
type TM = (mA, mB, mC); TMs = set of TM;
function F: TMs; begin F := [mA, mC]; end;
var m: TM;
begin for m in F do Write(Ord(m), ' '); WriteLn; end.
```

pxx: `error: for-in: not a generator, enum type, or iterable variable`
fpc 3.2.2: accepts, prints `0 2 `.

## The boundary, measured — this is the part not to re-derive

| shape | result |
| --- | --- |
| `for m in F` where `F: TMs` (set) | **refused** |
| `for i in F` where `F: array of Integer` | works, `7 9` |
| `for m in F.s` where `F: TR` and `TR.s: TMs` | works, `0 2` |
| `s := F; for m in s` | works, `0 2` — the workaround |

So `for-in` over a CALL is not the problem; the dyn-array result goes through
fine. It is the SET result specifically.

## Why it is filed separately from the parameter bug

Its diagnostic comes from a different place. The parameter defect reached
`BuildForInSetLoop` and was refused there by the *element-kind* test
(`set iteration supports set of <enum>, set of Char or an ordinal set
constructor`) because the symbol carried no element kind. This one never gets
that far — the container dispatch does not recognise a call node with a set
result as an iterable at all, and says so with the *other* message. Fixing the
stamp did not move it, which is the evidence, not the reasoning.

## Where to look

`ParseForInSetAST` takes a SYMBOL (`setSym`), and the qualified-lvalue path
(`ParseForInNodeAST`, `pasparser_stmt.inc:~1413`) already handles a set reached
through a node rather than a symbol — that is why the record-field row works. A
call result is a third source with no arm. The element identity is available on
the proc (`ProcRetType` and the set columns beside it) the same way the field
path reads `UFldSetEnumId` / `UFldSetElemTk`.

Note the temp-assignment workaround already materialises the result into a
symbol, so whatever the fix does, it must not evaluate `F` once per loop
iteration — the membership scan runs the container expression's node, and a
call with side effects would fire 256 times.

## THE CARRIER CENSUS — frankB, 2026-09-06, and it is why this is not a one-line arm

A set's ELEMENT IDENTITY is carried once per CARRIER, and the carriers are
independent parallel columns in four files:

| carrier | column |
| --- | --- |
| variable | `SymSetEnumId` / `SymSetElemTk` (`defs.inc:3286`) |
| record field | `UFldSetEnumId` / `UFldSetElemTk` (`defs.inc:5894`) |
| property | `UPropSetEnumId` (`defs.inc:5951`) |
| parameter | `ProcParamSetEnumId` (`defs.inc:3524`) |
| type alias | `AliasSetElemTk` (`defs.inc:6037`) |
| **function RESULT** | **none — `ProcRetEnumId` exists, `ProcRetSetEnumId` does not** |

`defs.inc:3525` already names this family in prose, in its own words — *"the
five-carrier set (symbol / record field / type alias / array element /
param-return)"* — for a DIFFERENT fact (managed-string element width). So the
enumeration exists, as a comment, and the sixth carrier is missing anyway.
**That is a worked example of a written-down list failing to surface an
omission, sitting in the file today.** A list nothing is forced to walk is a
comment, which is the same rule as: a precondition you do not branch on is a
comment.

### The order of work, and why the column is NOT being added first

The refusal today comes from the container DISPATCH
(`pasparser_stmt.inc:~2930`), one layer earlier than any element-identity
question — it would refuse a set-returning call even if the identity were
present, because a call result is a third source of a set and only two have an
arm (`ParseForInSetAST` takes a symbol, `ParseForInNodeAST` takes a node whose
kind is `AN_IDENT` or `AN_FIELD`).

So: **add the dispatch arm, re-measure, and add a carrier only if the compiler
then says it does not know the element type.** Adding two columns on a
hypothesis is how a plausible explanation gets built into the tree, and a
plausible explanation for a red is this repo's expensive failure mode.

### The constraint the fix must satisfy, which is not about parsing

`BuildForInSetLoop` scans the set's DOMAIN and reads the container node per
candidate. `CloneAST(contNode)` on a CALL node would therefore emit the call
inside the loop — up to 256 evaluations for a `set of Char`, side effects and
all. The container must be materialised into a hidden local ONCE, which is the
move the dyn-array and fixed-array call-result arms in `ParseForInNodeAST`
already make and document. fpc evaluates it once; `test_for_in_over_a_set_valued_call`
row E asserts `calls=2` and is the row a fix that merely stops the refusal
still fails.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a8b54edf1.
