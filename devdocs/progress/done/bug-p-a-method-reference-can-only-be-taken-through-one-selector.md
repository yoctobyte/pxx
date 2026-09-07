---
slug: bug-p-a-method-reference-can-only-be-taken-through-one-selector
title: "`@a.b.Foo` does not compile: a method reference can only be taken through exactly ONE dot, so no event can be wired to a method of a nested object"
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-07
resolved: 2026-09-07
resolution: 5af8bcfcf
summary: "`@Form.Button.Click` -- a method reference through a chain of selectors, which is how every form wires an event -- did not compile. The `@` arms in pasparser_expr.inc are each written for depth 1: the selector walker takes every `.` it can reach, so the FINAL one became a CALL. Three messages, one cause: `@o.Inner.Foo` gave `wrong number of parameters in call to TInner.Foo`, `@g.Mk.Foo` gave `a statement cannot start with '.'`, `@TG.Create.Foo` gave `@TG.Create: unknown method` (the class-TYPE arm reads one dot and asks FindUMeth, and a CONSTRUCTOR is not in that table). FIXED by telling the walker where to stop: AtStopDotTok names the one dot it must leave in the stream, LastDotOfDesignator finds it by lookahead, and the `@` arm resolves that last name itself into the AN_METHODREF the depth-1 arm already knew how to build -- VMT slot included. Fixture test_mpchain26, six rows against the fpc 3.2.2 oracle. Burns tgeneric107.pp. NOT fixed and filed separately: the DELPHI no-`@` spelling of the same chain (tgeneric106.pp)."
---

# The shape

```pascal
type
  TLeaf  = class X: Integer; function Add(const aX: Integer): Integer; end;
  TMid   = class Leaf: TLeaf; end;
  THolder= class Mid: TMid; end;
var f: function(const aX: Integer): Integer of object;
...
f := @h.Mid.Leaf.Add;      { wrong number of parameters in call to TLeaf.Add }
f := @h.Mid.Self_.Leaf.Add;{ a statement cannot start with '.'               }
f := @TLeaf.Create.Add;    { @TLeaf.Create: unknown method                   }
```

fpc 3.2.2 compiles and runs all three.

# The cause, and why it read as three bugs

The `@` handler has five hand-rolled arms and **every one of them is written for
exactly one dot**: obj/member, obj/field, obj/method, bare implicit-`Self`
method, and class-type/method. Depth 2 falls into whichever arm matches the
FIRST selector, and that arm then hands the tail to
`ParseClassRecordSelectors` — which consumes every `.` it can reach, so the
method at the end becomes a **call**.

**The error text depends on where the truncated parse stopped, not on the
defect.** That is why the same cause reads as a parameter-count error, a
statement-parser error and a name-resolution error, and why the three were never
put together. `bug-p-at-over-a-class-base-consumes-only-one-selector` (done) is
the same family one step earlier: it fixed the *address* case and left the
*method reference* case, because an address needs the whole chain walked and a
method reference needs the chain walked **one selector short**.

# The fix

The value half and the reference half end in different places and the walker had
no way to be told so. So it is told:

- `AtStopDotTok` (defs.inc) — the one token index `ParseClassRecordSelectors`
  must not walk through, or −1. An **absolute token index**, deliberately: a
  nested parse inside the chain (`@o.Items[i + 1].Ev`) runs the same walker over
  different tokens and can never collide with it, because the stop dot is at the
  outer level by construction. A flag or a countdown would need saving and
  restoring at every nested entry, which is the shape this kind of parser state
  gets wrong.
- `LastDotOfDesignator` (pasparser_name.inc) — pure lookahead over the same three
  postfix openers the walker has (`.` name, `[…]`, `(…)`). It resolves no name,
  so it can be wrong about extent and never about types.
- Two arms in pasparser_expr.inc: the instance-base one parses the chain as a
  value and resolves the last name itself; the class-type one has a different
  *value* parser rather than a different resolution — `TG.Create` is an ordinary
  factor, so it recurses into `ParseFactor` with the stop set instead of growing
  a sixth hand-rolled walk.

Both gate on the last dot not being the first, so **every depth-1 designator
keeps the existing arms untouched**: the population this opens is exactly the
designators that could not compile at all.

When the name after the stop is NOT a method it is a field or a property and the
answer is an address, so the walk resumes with no stop and `AN_ADDR` is taken
over the whole chain — the same result the old arm produced, reached one
selector later.

# Measurement

Fixture `test/test_a_method_pointer_can_be_taken_through_a_chain_of_selectors.pas`,
six rows, all matching fpc 3.2.2. Positive control on pin v407: three of the six
rows are refused there, with all three of the historical messages.

Row 5 is the one that can fail quietly. `THolder.Item` is declared `TBase` and
holds a `TDerived`, so a reference that dropped the VMT slot would call
`TBase.Speak` and print `base` — a plausible answer, not a crash, and the exact
defect `bug-a-method-pointer-virtual-captures-static-address` records at depth 1.
There is deliberately no `TBase(h.Item).Speak` row beside it: a cast then a CALL
still dispatches virtually, so it prints `derived` under a broken compiler too.

# Residual

`tgeneric106.pp` does NOT burn and is a different mechanism, filed as
[[bug-p-a-delphi-parenless-method-reference-cannot-have-a-chained-receiver]]:
Delphi mode takes a method reference with no `@` at all, and
`TryParseParenlessMethodRef` reads exactly `Ident . Ident`. Its depth-1 form
works; only the chained receiver fails. It is the fifth receiver spelling of
`bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings`
(done), and it is harder than this one because that arm parses SPECULATIVELY and
must consume nothing when it decides the shape is a call.
