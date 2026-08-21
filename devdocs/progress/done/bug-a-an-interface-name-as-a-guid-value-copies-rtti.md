---
track: A
prio: 50
type: bug
blocked-by: []
summary: "`g := IHello` — an interface name used as a value, which in Pascal means its GUID — copied 16 bytes of the interface's RTTI BLOB into the TGuid instead: two pointers where a GUID belonged, silently, with GetInterface then answering False for an interface the object plainly implements. Fixed with a real AN_GUIDCONST node typed as TGuid; the same node then made Supports' three-argument form and a failing query's out-parameter clearing fall out almost free. Found by an OOP differential against FPC 3.2.2."
---

# An interface name used as a GUID value copied the RTTI blob

- **Type:** bug (**silent wrong VALUE**, no diagnostic) — Track A
  (`defs.inc`, `pasparser_lval.inc`, `pasparser_call.inc`, `pasparser_expr.inc`,
  `symtab.inc`, `ir.inc`, `compiler/builtin/builtin.pas`).
- **Status:** done
- **Opened:** 2026-08-21, from the OOP differential against FPC 3.2.2.
- **Closed:** 2026-08-21.

## Symptom

```pascal
type IHello = interface ['{11111111-2222-3333-4444-555555555555}'] ... end;
var g: TGuid;
begin
  g := IHello;
  { print the 16 bytes }
end.
```

```
fpc:  11 11 11 11 22 22 33 33 44 44 55 55 55 55 55 55
pxx:  31 4E 44 00 00 00 00 00 D9 3D 44 00 00 00 00 00
```

Those pxx bytes are two data-section pointers. The consequence downstream is the
part that bites:

```pascal
g := IHello;
ok := impl.GetInterface(g, f);     { fpc: True.  pxx: False }
```

— an object is told it does not implement an interface it plainly implements,
with no error anywhere. Nothing in the program looks wrong; the query simply
answers the wrong thing.

## Root cause

An interface name in an expression fell through to the branch that handles a
CLASS name used as a value, which builds `AN_CLASSREF` — the address of the
class's RTTI blob. The assignment to a 16-byte record then did what it was told:
copy 16 bytes from that address. The blob's first 16 bytes are its name pointer
and its parent pointer, so the result was well-formed garbage.

But an interface is not a class in this position. It has no metaclass and no
class reference; the only thing an interface name can mean as a *value* is its
GUID, and `AN_CLASSREF` was simply the wrong node. The GUID bytes existed all
along — `ParseGuidLiteral` had already parsed them into `UClsGuidB` in TGuid
memory order, precisely so a compile-time blob and a runtime `TGuid` compare
byte for byte.

## Fix

`AN_GUIDCONST` (node 100): ASTIVal is the interned-string index whose 16 bytes
are the GUID; `IRLowerAST` yields the blob's data address, and — the part that
matters — `IRLowerAddress` yields the same address, because for this node the
value and its address are the same thing.

The node is typed as the **record `TGuid`**, not as a pointer. That is what lets
the ordinary record paths carry it with no special cases: copy on assignment,
by-address for a `const` parameter, and overload matching against
`const IID: TGuid`. `RegisterBuiltinTGuid` mints that record unconditionally, so
the lookup cannot miss.

An interface with no GUID literal now gets an explicit error
(`interface "INoGuid" has no GUID, so it has no value form`) instead of the old
silent blob copy.

### The half-a-struct detour

Typing it as a record was not enough on its own: `ShowG(IHello)` — the name as a
`const TGuid` argument — delivered **eight correct bytes and eight zeros**.
`ResolveNodeRec` did not know the node, answered `REC_NONE`, and the argument
temp took the 8-byte fallback. That is the same signature the `AN_ASSIGN` arm of
that very function already documents from a csmith seed, three comment-lines
above where the fix went in — a struct arriving half-initialised, every value
derived from the first field correct, which is what makes it take a checksum to
notice.

## What it unlocked

With a GUID constant available as a node, two further gaps closed almost free —
both verified against FPC in the same test:

- **`Supports(obj, IFoo, Intf)`**, the three-argument form, did not parse at all
  (`unexpected token`). FPC defines it as
  `Result := (Instance <> nil) and Instance.GetInterface(IID, Intf)`, so it now
  lowers to exactly the `__pxxGetInterface(obj, @guid, @Intf)` call that
  `obj.GetInterface(IFoo, Intf)` already built — not a second interface-lookup
  path beside the one that exists. The two-argument form still lowers to
  `AN_IS_TEST` and is untouched.
- **A failed query left the out-parameter set.** `Supports(pl, IHello, f)`
  returning False left `f` holding the interface from a *previous* successful
  query. FPC declares `out Obj` and clears it. Fixed inside
  `__pxxGetInterface`, where both spellings funnel, since a stale interface
  surviving a failed `Supports` is a use-after-free waiting to happen rather
  than a cosmetic difference.

## Verification

`test/test_interface_guid_and_supports.pas`, wired into `test-core`, and
**byte-identical to fpc 3.2.2** across twelve rows: the GUID bytes in TGuid
memory order, two interfaces staying distinct, the same interface named twice
staying stable, the name as a `const TGuid` argument, the name passed straight
to `GetInterface`, the three-argument `Supports` hitting and missing, the
clearing rule, a nil instance, the two-argument form in both directions, and the
`if Supports(...) then` shape it is actually written in.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Not done

`__pxxGetInterface` stores the instance pointer into the interface slot
**without an AddRef**, so the slot holds a borrowed reference — which is why the
clearing above is a plain store rather than a release. That predates this work
and is unchanged by it; filed as `feature-a-getinterface-refcounting`.
