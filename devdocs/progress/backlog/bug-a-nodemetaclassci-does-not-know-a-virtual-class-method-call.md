---
track: A
prio: 65
type: bug
blocked-by: []
summary: "NodeMetaclassCi (symtab.inc) recognises a metaclass-valued function RESULT only as AN_CALL, but GenMakeStaticMethodCall rewrites the node kind to AN_CLASS_VIRTUAL_CALL when the class method is VIRTUAL. So `AFactory.GetSvc.Lookup(x)` — a virtual class function returning `class of T`, the shape Generics.Defaults uses — falls past the metaclass branch and dies as `\"Lookup\": a pointer has no members`. The predicate's own comment says it exists so the next spelling is added once; this is that spelling. Blocks rung 3 of the Pascal corpus at generics.defaults.pas:3341."
status: backlog
owner: unassigned
---

# NodeMetaclassCi does not know a virtual class-method call

Filed by frankA (Track P) under the frontend rule: the fix is in
`compiler/symtab.inc`, which is Track A's shared ground, so this is filed rather
than fixed. It is the current wall of [[feature-pascal-corpus-generics]] (rung 3)
at `generics.defaults.pas:3341`.

## The corpus line

```pascal
Exit(AFactory.GetHashService.LookupEqualityComparer(ATypeInfo, ASize));
```

`AFactory: THashFactoryClass` (`class of THashFactory`), and
`GetHashService: THashServiceClass; virtual; abstract` — a **virtual class
function returning a metaclass**. Reduced to 30 lines, fpc-oracled (prints 42):

```pascal
type
  TSvc = class class function Lookup(n: Integer): Integer; static; end;
  TSvcClass = class of TSvc;
  TFactory = class class function GetSvc: TSvcClass; virtual; end;
function Drive(AFactory: TFactoryClass): Integer;
begin
  Result := AFactory.GetSvc.Lookup(21);     { "Lookup": a pointer has no members }
end;
```

## Root cause

`NodeMetaclassCi` (`symtab.inc`) answers "which class does this node's metaclass
value refer to" for five spellings, the fifth being a function result:

```pascal
  else if ASTKind[node] = AN_CALL then ...ProcRetPtrElemRec[si]...
```

But `GenMakeStaticMethodCall` (`pasparser_call.inc:1361`) builds `AN_CALL` and
then, for a virtual class method, **replaces the kind**:

```pascal
  if GenVirtSlot >= 0 then
  begin
    ASTKind[callNode] := AN_CLASS_VIRTUAL_CALL;   { 88, not 8 }
```

so the predicate returns -1, the metaclass branch in `ParseLValueAST` is skipped,
and the chain falls through to the `tk = tyPointer` / `recName = REC_NONE` guard,
which reports `a pointer has no members`.

The predicate's comment already frames the fix: *"The first four were each taught
to be a receiver one ticket at a time... One predicate instead of five arms, so
the next spelling is added once."* This is the sixth spelling — it belongs in the
existing `AN_CALL` arm, not in a new branch.

## Evidence — `virtual` is the whole variable

fpc answers 42 for every row.

| receiver | `GetSvc` | pxx |
| --- | --- | --- |
| `class of` value | **virtual** | REFUSED `a pointer has no members` |
| `class of` value | non-virtual | 42 |
| instance | **virtual** | REFUSED `no such member on this record/class` |
| instance | non-virtual | 42 |

Non-virtual leaves the node as `AN_CALL` and works; virtual rewrites it to
`AN_CLASS_VIRTUAL_CALL` and fails. `PXXDBG=a.ast` on the working arm confirms
`kind=8` for the intermediate call. `AN_CALL = 8` / `AN_CLASS_VIRTUAL_CALL = 88`
(`defs.inc:332`, `:512`).

The **instance** row's different message is probably the same missing identity
surfacing at a different diagnosis site, but that is inference, not measurement —
confirm it with the fix rather than assuming it.

## Related, and already handled

- [[bug-a-a-metaclass-returned-from-a-function-is-not-a-receiver]] (done) — the
  ticket that created this predicate. This is its next spelling.
- [[bug-p-a-class-method-call-keeps-the-receivers-class]] (fixed, Track P) — a
  different defect found in the same sweep; does not fix this one.
- [[bug-p-a-call-chained-onto-a-class-method-result-is-dropped]] — also separate,
  also still open.

## Gate

Track A's: `make test` + self-host byte-identical. The 30-line repro above is the
regression test; keep the non-virtual arm in it as the control.
