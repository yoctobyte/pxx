---
track: A
prio: 65
type: bug
blocked-by: []
summary: "NodeMetaclassCi (symtab.inc) recognises a metaclass-valued function RESULT only as AN_CALL, but GenMakeStaticMethodCall rewrites the node kind to AN_CLASS_VIRTUAL_CALL when the class method is VIRTUAL. So `AFactory.GetSvc.Lookup(x)` — a virtual class function returning `class of T`, the shape Generics.Defaults uses — falls past the metaclass branch and dies as `\"Lookup\": a pointer has no members`. The predicate's own comment says it exists so the next spelling is added once; this is that spelling. Blocks rung 3 of the Pascal corpus at generics.defaults.pas:3341."
status: done
owner: frankA
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

## Resolved 2026-08-29 (frankA, sole-A, combined-track self-resolve)

**The ticket named one missing row and there were three.** Filed as "the sixth
spelling"; it is the sixth, seventh and eighth. Measured before touching the
predicate, each shape in its own program because the compiler aborts on the
first error and one refusal hides the rest:

| spelling of the metaclass-returning call | node kind | before | after |
| --- | --- | --- | --- |
| plain function | `AN_CALL` (8) | 42 | 42 |
| non-virtual class method | `AN_CALL` | 42 | 42 |
| non-virtual instance method | `AN_CALL` | 42 | 42 |
| **virtual class method** | `AN_CLASS_VIRTUAL_CALL` (88) | REFUSED | 42 |
| **virtual instance method** | `AN_VIRTUAL_CALL` (32) | REFUSED | 42 |
| **interface method** | `AN_INTF_CALL` (58) | **4258231 — silent** | 42 |

fpc 3.2.2 answers 42 for every row. The interface row is the one the ticket
missed entirely, and it was the silent one.

### Was the predicate's premise right? Half.

The comment says the predicate exists so *"the next spelling is added once"*, and
the instruction was to flag it if adding one needed more than an enumeration entry.

**For the two virtual spellings the premise held exactly** — one condition, three
node kinds, no other change, both fixed.

**For the interface spelling it did not, and that is the bigger finding.** Adding
`AN_INTF_CALL` to the predicate changed nothing, because that path never reaches
the predicate: the interface arm in `pasparser_lval.inc` ended

```pascal
  node := mcallNode;
  Result := node; Exit;        { <-- drops every trailing selector }
```

so `g.IGet.Lookup(21)` never asked what `g.IGet` was — the `.Lookup(21)` was
discarded and the expression evaluated to the intermediate result. A predicate
cannot answer a question nobody asks it. Fixed by continuing the selector loop
and setting `tk`/`recName` from the result, the same three lines the class-method
and instance-method arms carry.

So the enumeration is the right design and was not the whole defect: **one bug
was a missing table row, the other was a caller that never consulted the table.**

### Why the row was under-specified

Not carelessness — a category slip. The five rows enumerate **where the pointee
is stored** (`Syms[].PtrElem*`, `AliasElem*`, `UFldPtrElem*`, `ProcRetPtrElem*`),
and on that axis "a function result" really is one row. But the row also has to
match a **node kind**, and there are four kinds meaning "a call": one is built and
then rewritten in place by whoever knows the dispatch —
`GenMakeStaticMethodCall` swaps in `AN_CLASS_VIRTUAL_CALL`, the instance arm
allocates `AN_VIRTUAL_CALL`, the interface arm `AN_INTF_CALL`. One axis was
complete and the other was not.

All four keep the `Procs[]` index in `ASTIVal` — the vtable/IMT slot rides in
`ASTSOffset` or `ASTRight` — which is *why* one lookup can serve them; that was
checked against each builder before widening the condition, since indexing
`Procs[]` with a vtable slot would have been a silent wrong answer of my own.

### Sibling checked, per the standing rule

The obvious twin of "virtual class function returning a **metaclass**" is one
returning an **instance**. Built the same six-spelling program with `class of T`
replaced by `T`: all six rows correct, matching fpc. (Its interface row was
broken before today too, and is fixed by the same selector-loop change.)

### Corpus

`generics.defaults.pas` is past **3341**; the next stop is a different failure
class again — `@TEquals.Class: the address of a routine with no body was taken`.
Trust `near:` over `in:` there, as this rung's notes say: `in:` named
`builtinheap.pas` while `near:` showed generics.defaults tokens.

### Files, and the boundary

`compiler/symtab.inc` (the predicate) and `compiler/pasparser_lval.inc` (the
interface arm). **No backend was touched** — `ir_codegen_*.inc` are the O
campaign's and were not opened.

### Gate

`make compiler/pascal26` fixedpoint `fd7a0e752dec`, `tools/forwardlint.py` clean,
`gate.sh quick` GREEN. `test/test_metaclass_call_spellings.pas` is fpc-oracled,
carries the three always-working spellings as controls, and was **confirmed
refused on the baseline first** (line 53).

## Log
- 2026-08-29 — resolved, commit 72dbc9ba0.
