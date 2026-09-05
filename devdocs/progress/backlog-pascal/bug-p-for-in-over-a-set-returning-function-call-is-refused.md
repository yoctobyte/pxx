---
prio: 35
track: P
summary: "`for x in F` where F is a function RETURNING A SET is refused with `for-in: not a generator, enum type, or iterable variable`; fpc 3.2.2 accepts it and prints `0 2`. NARROW AND MEASURED: the same loop over a DYNARRAY-returning function works, and so does `for m in F.s` where F returns a RECORD holding the set -- so this is not `for-in over a call` in general, it is the SET result specifically. Assigning to a temp first (`s := F; for m in s`) works and is the workaround. Found beside bug-p-a-set-parameter-loses-its-element-kind-so-for-in-refuses-it and deliberately NOT folded into it: that one was a missing symbol stamp on a parameter, this one never reaches the set path at all (different diagnostic, from the container dispatch rather than from BuildForInSetLoop), so a fix for one is no evidence about the other."
---

# `for x in F` is refused when F returns a set

- **Type:** bug — Track P (Pascal frontend)
- **Status:** backlog, unclaimed
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
