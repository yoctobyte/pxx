---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: "frankB"
created: 2026-09-06
summary: "Both Pascal receiver arms resolve a class var through an instance and then clear the RECORD IDENTITY (`recName := REC_NONE`) while the selector loop continues, so a class var or class const selected off another class var has no namespace to be looked up in and becomes a read at offset 0: `c.Inner.IV` printed 4265192 where fpc prints 22, the same constant for every member tried, while `TC.Inner.IV` on the very same object was right. Silent wrong value, no diagnostic. Breaks only when BOTH links are per-class -- an instance field off the same chain re-derives the record further down and was correct -- which is why two working neighbours sat on either side of it."
---

# A chained class var of class type loses its record identity

- **Type:** bug — **Track P** (`compiler/pasparser_lval.inc`, four sites).
- Found while widening the fixture for
  [[bug-p-a-class-const-is-unreachable-through-an-instance-receiver]] and
  confirmed PRE-EXISTING by a positive control: the fix for that ticket was
  reverted, the compiler rebuilt, and the same garbage came back.

## Repro

```pascal
type
  TInner = class
    class var IV: LongInt;
  end;
  TC = class
    class var Inner: TInner;
  end;
var c: TC;
begin
  TC.Inner := TInner.Create;  TInner.IV := 22;  c := TC.Create;
  WriteLn(TC.Inner.IV);   { pxx 22        fpc 22 }
  WriteLn(c.Inner.IV);    { pxx 4265192   fpc 22 }
end.
```

## Cause

`ParseLValueAST` and `ParseClassRecordSelectors` each resolve a class var
reached through an instance, build an `AN_IDENT` over the shared backing
symbol, and then set `recName := REC_NONE` / `recId := REC_NONE` before
`Continue`ing the selector loop. The class var's own record identity is gone,
so whatever selector comes next has nothing to be looked up in.

The same clearing sits on the typed-class-const symbol arm beside each of them
— four sites, and they are two pairs of a double case.

## Why it hid

**The shape only breaks when BOTH links are per-class.** An instance FIELD off
the same chain re-derives the record from the node further down the loop, so
`c.Inner.SomeField` was right. The class-var arm is the one that asks
`FindClassVar(recName - REC_UCLASS_BASE, ...)` **directly**, so REC_NONE takes
it past every arm to the no-namespace fallback and it reads at offset 0 —
returning the same constant for every member tried, which is the tell that no
member was being read at all.

A second trap sat on top of it: **`class var` opens a SECTION.** In

```pascal
TInner = class
  class var IV: LongInt;
  F: LongInt;
end;
```

`F` is a class var too, under both compilers (`a.F := 1; b.F := 2` leaves both
reading 2). Two probes written to contrast a class var with an instance field
were contrasting a class var with a class var, and the boundary only appeared
once a `var` section was re-opened.

## Fix

Carry the identity instead of clearing it, at all four sites:

```pascal
if (tk = tyClass) or (tk = tyRecord) then recName := ResolveNodeRec(node)
else recName := REC_NONE;
```

`ResolveNodeRec` on an `AN_IDENT` is `SymRecOf(ASTIVal)`, which is the same
question the field path already asks.

## Gate

`test/test_a_class_var_of_class_type_carries_its_record_identity_through_a_chain.pas`
— thirteen rows, `test-core`, byte-identical to fpc 3.2.2: the class-var and
class-const links, an instance field and a method off the same chain, the
lvalue side, a class var of RECORD type, a two-link chain, a parenthesised
receiver (the second arm), a typed record class const (the symbol arm), and the
two QUALIFIED spellings as controls, which were correct throughout.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 257f40288.
