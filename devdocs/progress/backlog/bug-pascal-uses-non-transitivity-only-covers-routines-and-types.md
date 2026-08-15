---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`uses` went non-transitive by default (56a540143) but the rule reaches only ROUTINES and named TYPES, and only for an IMPLEMENTATION-section uses. Constants, variables and enum members still leak through, and an INTERFACE-section uses still re-exports everything including routines. Two independent axes; FPC rejects all of it."
---

# Non-transitive `uses` covers routines and types, not consts/vars/enums — and not interface-section uses at all

- **Type:** bug — **Track A** (shared `parser.inc` / `symtab.inc` visibility).
- **Follows:** [[bug-pascal-uses-is-transitive]], resolved 2026-08-15 (`56a540143`)
  — the default flip. That ticket's headline repro (`IntToStr` reached through
  `priv`'s implementation-section `uses sysutils`) genuinely behaves now. The
  rule is simply narrower than "non-transitive".
- **Found by:** the user asking whether constants were covered too. They were
  not, and the measurement turned up a second, larger axis on the way.

## The measurement

Leaf unit declares one of each kind; `umid` reaches it; `p` uses only `umid`
and names the leaf symbol directly. FPC 3.2.2 `-Mobjfpc` is the oracle and
rejects **every** row below with `Identifier not found`.

### Axis 1 — symbol KIND (`umid` has `uses uleaf` in its IMPLEMENTATION)

| leaf symbol | pxx | correct? |
| --- | --- | --- |
| `function LeafFunc` | `undefined variable (LeafFunc)` | yes |
| `type TLeafRec` | `unknown type: TLeafRec` | yes |
| `const LeafConst = 42` | **compiles, prints 42** | **NO** |
| `const LeafStr = 'leaf'` | **compiles** | **NO** |
| `var LeafVar` | **compiles** | **NO** |
| `type TLeafEnum` | **compiles** | **NO** — an enum TYPE, where `TLeafRec` is caught |
| enum member `leB` | **compiles** | **NO** |

So the filter is applied to the routine table and to *some* of the type table,
and to neither the constant table nor the variable table. `TLeafEnum` slipping
while `TLeafRec` is caught is the tell that this is per-table plumbing, not one
rule with holes — worth finding out which lookup path enums take before
patching, because that difference is likely to be the whole bug on this axis.

### Axis 2 — uses SECTION (`umid` has `uses uleaf` in its INTERFACE)

| leaf symbol | pxx | correct? |
| --- | --- | --- |
| `function LeafFunc` | **compiles** | **NO** |
| `type TLeafRec` | **compiles** | **NO** |
| `const LeafConst` | **compiles** | **NO** |

Everything leaks, including the two kinds axis 1 gets right. This is the bigger
half: an interface-section `uses` is **not** a re-export in Pascal, and FPC
proves it. Clients of `umid` must not see `uleaf` at all, and today they see
all of it.

The likely cause is that the visibility edges are built per-unit rather than
per-(unit, section), so an interface `uses` is either recorded as a
public/re-exporting edge or not recorded as a boundary at all — whereas the
implementation-section case has the boundary the resolved ticket built. Check
`UsesEdge*` / `VisibilityAllows` / `DeclVisible` before assuming.

## Repro

```pascal
{ uleaf.pas }
unit uleaf;
interface
const LeafConst = 42;
implementation
end.

{ umid.pas — either section reproduces its own axis }
unit umid;
interface
uses uleaf;          { axis 2: leaks EVERYTHING }
implementation
{ uses uleaf; }      { axis 1: leaks consts/vars/enums only }
end.

{ p.pas }
program p;
uses umid;           { uleaf appears NOWHERE in this program }
begin WriteLn(LeafConst); end.   { 42 — should be "undefined" }
```

## Why this is not just "finish the job"

Axis 2 is a much wider blast radius than the resolved ticket's change was: an
interface-section `uses` is the *common* spelling, so closing it will surface
every source in the tree that leans on a re-export. The resolved ticket's flip
was safe partly BECAUSE it only reached implementation-section uses — the
corpus sweep that returned 0 findings was measuring the narrow rule, and its
number does not transfer.

So this ticket should NOT be landed as one flip on the strength of that sweep.
Suggested shape, mirroring what worked:

1. Fix axis 1 (kinds) first — small, and inside a boundary the corpus has
   already been swept against.
2. Put axis 2 behind the existing `--strict-uses` flag (which the flip left as
   an accepted no-op — it can carry meaning again), sweep the corpus with it,
   fix the fallout, then flip.

`--no-strict-uses` already exists as the escape hatch and covers both.

## Gate

`make compiler/pascal26` + the repro above in both sections + `tools/gate.sh
quick`. Every row's oracle is FPC 3.2.2 under `-Mobjfpc` (required: in default
FPC mode `Integer` is 16-bit and several rows answer a different question).
Axis 2 additionally wants a Track T corpus sweep before its default flip.
