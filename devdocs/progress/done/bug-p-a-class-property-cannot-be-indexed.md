---
slug: bug-p-a-class-property-cannot-be-indexed
title: "A class property cannot take arguments -- neither a declared subscript nor `index N` reaches the accessor"
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankA
created: 2026-09-05
summary: "Both spellings that give a class property's accessor an argument were broken through the class name, and both work through an instance. `TC.A[2] := 7` picked the READ accessor (the `:=` peek was zero-lookahead and saw the `[`); `WriteLn(TC.A[2])` left the `[` behind as `expected ')' before '['`; and `class property P: T index N` built its constant with PropIndexConstArg and then DROPPED the chain on the write side, never calling it at all on the read side. One arm, hand-building the accessor call instead of using the four helpers in pasparser_call.inc."
---

# Measured 2026-09-05, fpc 3.2.2 as the oracle, pin-independent (probes run on the tip)

```
                                 pxx before        pxx now / fpc
TC.A[2] := 7                     wrong number of parameters in call to TC.GetA
WriteLn(TC.A[2])                 expected ')' before '['        107
class property P0 index 4        wrong number of parameters     41 42
```

The instance spellings of all three were already correct, which is why this
read as a missing feature rather than a bug: one concept, two resolution
paths, and the second one stayed broken.

# Cause

`ParseLValueAST`'s class-name arm (`TClass.member`) hand-builds its accessor
call. `pasparser_call.inc` carries four helpers whose whole purpose is that
eleven sites do not each get this wrong -- `ParsePropIndexArgs`,
`PropIndexConstArg`, `AccessorArgChain`, `MakeAccessorCall` -- and this arm used
one of them, for its return value, which it then threw away:

```pascal
{ the index constant, if the property declares one }
PropIndexConstArg(cpPri, margIdx, mexprNode);   { <- margIdx never linked }
```

Three separate defects fall out of the same omission:

1. **The `:=` peek is zero-lookahead.** `cpIsAssign` tested `CurTok` and one
   token past it. For an indexed property the `:=` sits after the whole bracket
   group, so a WRITE selected the getter. The instance arm a few thousand lines
   below already balances the brackets; this one did not.
2. **No subscript arm at all**, so `[` was left in the token stream for a caller
   with no use for it.
3. **`index N` reached neither direction** -- built and dropped on the write,
   never called on the read.

# Fix

The arm now parses its real arguments first (`ParsePropIndexArgs` when the
property declares a subscript, `PropIndexConstArg` otherwise), balances the
bracket group in the `:=` peek, and chains the setter's value after them with
`AccessorArgChain`.

It builds the call itself rather than through `MakeAccessorCall`, and that is
deliberate: `MakeAccessorCall` is the INSTANCE dispatcher, and a class method's
virtual dispatch reads the VMT out of the metaclass blob
(`AN_CLASS_VIRTUAL_CALL`), not out of `[Self+0]`. The no-argument read is left
on `GenMakeStaticMethodCall` verbatim, because that path also parses a trailing
`(...)` and this fix has no measurement about that behaviour.

# Test

`test/test_class_property_indexed.pas`, expected output fpc's own. The
assertion is the SHARING, not the compile: both `index` properties are two
names over ONE accessor pair, so a dropped constant lands them both on slot 0
and still prints a plausible number. Multi-index (`Cells[r, c]`) and a
subscript that is itself an indexed expression -- the case the `:=` peek has to
balance past -- are separate rows.

Negative control: the pre-fix compiler (`5fbd927465a6`) was rebuilt and refuses
the test on three rows.

# Found by

Taking `refactor-p-one-lvalue-path-for-statements-and-expressions`, whose own
open question is whether the shared walker can always decide "assignment
target" locally without a flag from the statement path. This is the measured
answer: **it cannot today** -- four arms peek for `:=` with a balanced
bracket scan and three peek with zero lookahead, and the difference is not
documented anywhere. That is a finding about the refactor, not an argument
against it: the fix was to make one more arm decide the way the careful ones
already do.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 527362dc9.
