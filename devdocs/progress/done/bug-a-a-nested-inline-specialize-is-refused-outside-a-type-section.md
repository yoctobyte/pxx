---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`specialize TBox<specialize TBox<Integer>>` was refused with `unknown type: specialize` in a var, a local, a record field, a parameter and a function result — every position except a type section, all five of which FPC accepts. The use-rewriting sweep collapses a `<...>` group only when its arguments are already plain idents, so nesting needs a second round; and cross-template nesting needs the EARLIER templates re-swept, because their own sweep ran before the inner template existed. Fixed by running the sweep to a fixed point over all templates."
---

# A nested inline `specialize` was refused outside a type section

- **Type:** bug (compile-time refusal of valid code) — Track A
  (`compiler/pasparser_generic.inc`, `defs.inc`).
- **Status:** done
- **Opened:** 2026-08-21, from a generics differential against FPC 3.2.2.
- **Closed:** 2026-08-21.

## Symptom

```pascal
var b: specialize TBox<specialize TBox<Integer>>;
```
```
pascal26:10: error: unknown type: specialize
```

Measured across the five positions a type reference can occupy — **FPC accepts
all five, pxx refused all five**:

| position | before | after |
| --- | --- | --- |
| `var` | refused | ok |
| local | refused | ok |
| record field | refused | ok |
| parameter | refused | ok |
| function result | refused | ok |

A **type section** already worked (`TNest = specialize TBox<specialize
TBox<Integer>>;`), which is what made this look like a niche gap rather than a
systematic one: the shape that gets written in a tutorial worked, and the four
that get written in real code did not. The workaround — name the inner
specialization with an alias first — is invisible to anyone who has not hit the
error, so the honest description is that inline nesting simply was not supported.

## Root cause

Inline `specialize TFoo<Args>` outside a binder position is handled by
`DelphiRewriteGenericUses`, a token-stream sweep that collapses each `<...>`
group into a minted alias ident and emits `alias = specialize TFoo<Args>;` ahead
of the use. Its argument collector accepts only plain type tokens, so on the
OUTER group of a nested use it meets the inner `specialize` ident, gives up
(`ok := False`), and leaves the literal word in the stream. The declaration
parser then reports the word `specialize` as an unknown type — the diagnostic is
honest, it just names a symptom four steps from the cause.

Two separate reasons one sweep is not enough:

1. **Depth.** A group is collapsible only once its arguments are plain idents.
   Round 1 can only rewrite the INNER group (`specialize TBox<Integer>`, whose
   own arguments are concrete) into `TBox$Integer`. Only then is the outer group
   in the shape the collector accepts.
2. **Template order.** The sweep runs once per template, right after that
   template is parsed, over the rest of the stream. So `TList`'s sweep runs
   *before* `TPair` exists, and could not have collapsed
   `specialize TList<specialize TPair<Integer, AnsiString>>` however deep it
   looked — the inner group belongs to a template that has not been read yet.

Reason 2 is why fixing only reason 1 leaves a working same-template case beside
a broken cross-template one, which is exactly the double case
`normalise-dont-special-case.md` describes. Both were fixed together.

## Fix

Run the sweep to a **fixed point over every template**:

```pascal
dgenAt := finalCur;
repeat
  dgenBefore := TokCount;
  for dgenT := 0 to TemplateCount - 1 do
    DelphiRewriteGenericUses(dgenT, dgenAt, TemplateIsDelphi[dgenT]);
  Inc(dgenRounds);
  if dgenRounds > 16 then Error('... nested deeper than 16 levels (or a rewrite loop)');
until TokCount = dgenBefore;
```

Three supporting changes:

- `insertAt` becomes a **var** parameter, so each round leaves it past the alias
  declarations that round emitted and the next round's aliases land *after*
  them. That ordering is the whole requirement: an outer alias refers to an
  inner one. The caller keeps its own `finalCur` untouched, so `TokPos :=
  finalCur` still lands on the first emitted declaration as before.
- `TemplateIsDelphi[]` records each template's surface syntax, because a sweep
  re-run over an earlier template must use *that* template's spelling, not the
  current one's.
- Termination: a round that rewrites nothing emits no alias declaration, so an
  unchanged `TokCount` means exactly "nothing left to collapse". The 16-round
  cap is a runaway guard, not a depth limit anyone will meet.

## Verification

`test/test_generic_nested_inline_specialize.pas`, wired into `test-core`,
**byte-identical to fpc 3.2.2** across six rows: nested inline `specialize` as a
var, a record field, a parameter, a function result and a local, plus the
cross-template case (`TList` over `TPair`, the outer template parsed first).

A broader twelve-shape generics harness was run alongside and matched FPC
everywhere else — plain and multi-parameter generic classes, generic records
with a static factory, independent instantiations, inheritance from a
specialization, an alias specialization, and managed (`AnsiString`) element
types with growth and free. So generics are in good shape; this was the one gap.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Note

One row of the exploratory harness diverged and is **not** a defect: a function
whose `Result` is never assigned on the taken path. FPC and pxx both return
whatever is there, and the values differ; that is undefined in both. It was
dropped from the wired test rather than blessed.
