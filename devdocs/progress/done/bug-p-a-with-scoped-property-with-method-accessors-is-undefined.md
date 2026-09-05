---
slug: bug-p-a-with-scoped-property-with-method-accessors-is-undefined
title: "A with-scoped property resolved only when its accessor was a FIELD; a getter/setter pair came out as `undefined variable`"
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankA
created: 2026-09-05
summary: "`with c do V := 5` over `property V: LongInt read GetV write SetV` was `undefined variable (V)`. ParseLValueAST's with-scope arm resolved a with-scoped property only through its BACKING FIELD slots and declined method accessors in a comment -- `method accessors are out of scope here (fall through)` -- and the fall through went past the field arm, past the `Free` desugar, past the method lookup (a property name is not a method name), out of the with loop and out of the compiler. Every other receiver already resolved the same declaration: `c.V`, a bare `V` inside a method, `Self.V`, `TCls.V`."
---

# Measured 2026-09-05, fpc 3.2.2 as the oracle

```
                                       pxx before                       pxx now / fpc
with c do V := 5                       undefined variable (V)           5 105
with c do A[3] := 33                   undefined variable (A)           33 133
with c do WriteLn(A[2])                this value cannot be indexed     9 109
```

The three OTHER spellings of the identical declaration were correct throughout
and are what says this is the arm and not the shape.

# Cause

The with-scope arm read the property's FIELD accessor slots
(`UPropReadFOff/Len`, `UPropWriteFOff/Len`) and built an `AN_FIELD` on the with
operand. A method-backed property has zero in those slots, so nothing was built
and nothing was reported -- the arm's own comment said *"method accessors are
out of scope here (fall through)"*, which is a record of the gap and not a
guard against reaching it.

# Fix

A method-accessor arm beside the field one, using `MakeAccessorCall` -- which
is correct here precisely because the receiver is an INSTANCE: Self goes at
argument 0 for a plain or virtual call and comes out of the fat pointer for an
interface. That three-way choice is the thing the eleven hand-rolled accessor
calls each got wrong in their own way, so this arm asks rather than builds.

The indexed spelling needed the second half of the same arm: `:=` follows the
SUBSCRIPT, so the direction peek has to balance the bracket group rather than
look one token ahead. It uses its own depth counter and not `w`, which is the
with-stack cursor of the enclosing loop.

# Test

`test/test_with_scoped_property_method_accessors.pas`, expected output fpc's
own. Every getter adds 100 and every setter stores plain, so a row that reached
the BACKING FIELD instead of the accessor prints a number 100 too small rather
than failing to compile -- which is the failure mode a with-scoped property
wrongly resolved as its own field would have. One row's subscript is itself an
indexed expression, so an unbalanced peek stops inside it.

Negative control: the pre-fix compiler (`b40a945ad173`) rebuilt and refuses the
test on four rows; restoring the fix rebuilt back to `0a1171771ffd`.

# Found by

Taking `refactor-p-one-lvalue-path-for-statements-and-expressions`, which asks
whether the shared walker can decide "assignment target" locally. Two arms
answered no in different ways on the same afternoon -- this one and
[[bug-p-a-class-property-cannot-be-indexed]] -- and both were the same
omission: an arm that resolves a property without going through
`pasparser_call.inc`'s accessor helpers.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e18cefa31.
