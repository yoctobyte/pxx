---
slug: bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized
track: P
prio: 70
type: bug
status: backlog
blocked-by: []
summary: "In {$MODE DELPHI}, `TOne<Integer>` where `TOne<T>` is declared in a USED UNIT is rejected with `unknown type: TOne`. Same-unit works; the objfpc `specialize TOne<Integer>` spelling works cross-unit; only the Delphi angle-bracket surface fails, and parameter count is irrelevant (a one-param generic fails). Cause is ordering, measured: DelphiRewriteGenericUses sweeps the SHARED Tokens[] array starting at `insertAt` — just after the template's own declaration — so a use that sits EARLIER in the array (the main program, lexed before the unit) is never rewritten. Blocks generics.collections.pas. Renamed from bug-p-a-generic-type-parameter-is-unknown-when-a-specialization-is-materialised-cross-unit: the original TKey framing was wrong."
owner: unassigned
---

# A Delphi-mode generic from a used unit cannot be specialized

Rung 9 of [[feature-pascal-corpus-expansion]], reached once
[[bug-p-a-forward-declaration-does-not-bind-a-differently-cased-body]] let
`generics.defaults.pas` compile end to end.

**Renamed and re-diagnosed 2026-08-29.** It was filed hours earlier as
*"a generic type parameter is unknown when a specialization is materialised
cross-unit"*, from the corpus error `unknown type: TKey` at
`generics.defaults.pas:790`. That framing was **wrong**, and it was filed
explicitly as *observed, not diagnosed* for exactly this reason. `TKey` is
incidental; so is the parameter count; so is the macro machinery. The real
defect is one notch more basic and reproduces in eleven lines.

## Repro — the boundary, measured against FPC

```pascal
unit uone;                          program b;
{$MODE DELPHI}                      {$MODE DELPHI}
interface                           uses uone;
type TOne<T> = class F: Integer; end;   var o: TOne<Integer>;
implementation                      begin o := nil; WriteLn(o = nil); end.
end.
```

| case | pxx | fpc |
| --- | --- | --- |
| two-param generic, **same unit** | TRUE | TRUE |
| **one-param** generic, **cross-unit**, Delphi `TOne<Integer>` | **`unknown type: TOne`** | TRUE |
| two-param generic, cross-unit, Delphi | **`unknown type: TTwo2`** | TRUE |
| one-param generic, cross-unit, **objfpc `specialize TOneO<Integer>`** | TRUE | TRUE |

The last row is the one that localises it: **the template IS importable and the
specialization machinery IS reachable across units.** Only the Delphi
angle-bracket *surface* fails. So this is not "generics do not cross units" — it
is the desugar that never fires.

## Cause — an ordering defect in the token rewrite

`DelphiRewriteGenericUses` (`pasparser_generic.inc:445`) turns the Delphi
surface into the objfpc one: each `TFoo<Concrete>` becomes a minted alias, with
one `TFoo$... = specialize TFoo<Concrete>;` inserted right after the template
declaration. It is called when the TEMPLATE is parsed, and it begins:

```pascal
  i := insertAt;                 { = just after the template's own declaration }
  while i < TokCount - 1 do
```

`Tokens[]` is **one array shared by every unit** (the same fact behind
`bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module`). The
main program is lexed before the unit it uses, so the program's
`var o: TOne<Integer>;` sits at a token index **below** `insertAt` and the sweep
never reaches it. The name then falls through to `ParseTypeKind`'s recovery arm
at `pasparser_decl.inc:735`, which reports `unknown type: TOne`.

That diagnostic is honest but distant: by then nothing remembers that `TOne` was
a generic or that a `<` followed it.

## Why this is NOT a one-line fix, and should not be microfixed

Starting the sweep at 0 is the obvious change and is wrong on both halves:

1. **Where does the alias go?** It is inserted "right after the template
   declaration, still inside the type section" — i.e. into the UNIT. An alias
   minted for a use in the main program has to be visible to the main program.
   Whether the unit's type section is the right home (it is exported, so it may
   be) needs to be established, not assumed.
2. **Idempotency.** This procedure is run to a fixed point and its own comments
   record `bug-a-the-delphi-generic-rewrite-is-not-idempotent` — a rewrite that
   inserted `specialize` in front of a group it had already rewritten, two
   tokens per round, forever. Widening the scanned range widens the surface that
   bug lived on.

Same family as wall 6's Delphi ordering defect (`GenericMethodCount=0` when the
Delphi specialization runs, because the rewrite emits near the top of the token
stream before method bodies are buffered). **Two ordering defects in one rewrite
is the "two mechanisms for one concept" smell** from
`devdocs/dev/root-cause-over-microfix.md`; whoever takes this should read wall
6's ticket first and consider whether one restructuring closes both.

## Hypotheses already refuted — do not spend these again

1. **`unknown type: TKey` means a type PARAMETER is out of scope.** No — `TKey`
   is just the first name the corpus reaches; a plain `T` fails identically.
2. **The `{$DEFINE X := ...}` macros.** `generics.collections.pas:30` sets
   `{$MACRO ON}` and defines its parameter lists as macros, so this is the
   obvious suspect. Measured, both work and match FPC:
   `{$DEFINE MYT := Integer}` used as a type, and
   `{$DEFINE PARAMS := TA, TB}` used as a **generic parameter list**
   (`type TPairX<PARAMS> = record`). Macro substitution is not the gap.
3. **The forward-decl case bug.** That was the previous wall, now fixed.

## Gate

The four-row table above matching FPC; `uses Generics.Collections` compiles;
`generics.defaults.pas` keeps compiling alone; the reduction lands in `test/`;
the per-fix loop.
