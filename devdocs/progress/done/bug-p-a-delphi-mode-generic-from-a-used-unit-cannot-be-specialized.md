---
slug: bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized
track: P
prio: 70
type: bug
status: done
blocked-by: []
summary: "In {$MODE DELPHI}, `TOne<Integer>` where `TOne<T>` is declared in a USED UNIT is rejected with `unknown type: TOne`. Same-unit works; the objfpc BINDER spelling works cross-unit but the INLINE one fails too (two arms, one fix), and parameter count is irrelevant (a one-param generic fails). Cause is ordering, measured: DelphiRewriteGenericUses sweeps the SHARED Tokens[] array starting at `insertAt` — just after the template's own declaration — so a use that sits EARLIER in the array (the main program, lexed before the unit) is never rewritten. Blocks generics.collections.pas. Renamed from bug-p-a-generic-type-parameter-is-unknown-when-a-specialization-is-materialised-cross-unit: the original TKey framing was wrong."
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
| cross-unit, objfpc **binder** `type X = specialize TOneO<Integer>;` | TRUE | TRUE |
| cross-unit, objfpc **inline** `var o: specialize TOneO<Integer>;` | **`unknown type: specialize`** | TRUE |

**The last two rows were one row, and splitting them is the point** (measured
2026-08-29). The original table recorded only "objfpc `specialize
TOneO<Integer>` — TRUE", which was the BINDER form; the INLINE form fails
cross-unit exactly like the Delphi surface. Both arms are the same defect —
`DelphiRewriteGenericUses` handles the Delphi surface as pattern A and the
inline `specialize` as pattern B, in one sweep, from one anchor — so one fix
closes both. They are listed separately because a green binder row is what makes
this look Delphi-only: check the inline row before closing.

The binder row is still the one that localises the defect: **the template IS
importable and the specialization machinery IS reachable across units.** Only
the sweep-anchored desugar fails. So this is not "generics do not cross units" —
it is the desugar that never fires.

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

**A third reason, and it is the one that decided the design — measured, not
argued (2026-08-29).** Sweeping from 0 was built and run. It passes every row of
the table above, and then breaks the moment a unit uses another unit: every
enclosing `ParseUsesUnitBody` frame holds a `savedTokPos` into a region lexed
EARLIER, and **neither `InsertTokens` nor `RemoveTokens` adjusts it** (they
adjust `AdjustPass2Spans` and `AdjustSrcRanges`, and nothing else). `program
nest; uses ua;` where `ua` uses `ub` and `ub` declares the template resumes three
tokens past where it stopped:

```
error: unexpected token in a unit interface section: it starts no declaration
  in: ua.pas
```

Compensating that properly needs a live-cursor mechanism in `lexer.inc` +
`defs.inc` — Track A's shared files. **That experiment was reverted whole**, and
the fact is worth keeping regardless of this ticket: *any token index held across
a unit boundary is invalidated by a token-stream edit below it, and only the
pass-2 spans and the source ranges are told.*

Same family as wall 6's Delphi ordering defect (`GenericMethodCount=0` when the
Delphi specialization runs, because the rewrite emits near the top of the token
stream before method bodies are buffered) — **but see the 2026-08-29 correction
at the top of [[feature-pascal-corpus-expansion]]: they did not share a fix.**
Wall 6 was closed on 2026-08-28 (`35f485537`) by giving the prerequisite SCAN a
third source, leaving this arm untouched. Asking the question was right; the
answer is no.

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

The table above matching FPC (**all five rows** — the inline objfpc arm is not
optional); `generics.defaults.pas` keeps compiling alone; the reduction lands in
`test/`; the per-fix loop. `uses Generics.Collections` compiling was written
into this gate and is **not** reachable from here — see the resolution note.

## Resolved 2026-08-29 (frankP) — sweep from the USES CLAUSE, not from the template

The invariant the fix rests on is structural rather than maintained: **a use of
an imported template cannot precede the `uses` that imports it.** So anchor the
sweep at the uses clause and every edit lands above the live cursor and above
every saved one *by construction* — nothing has to remember to adjust anything,
which is the difference between a fix and a fix that stays fixed.

New `DesugarImportedDelphiGenericUses` (`pasparser_generic.inc`) runs once at the
end of every uses clause and calls the existing `DelphiRewriteGenericUses` with
`insertAt := TokPos`. **A second call site, not a second implementation** — same
minting, same idempotency guards, same fixed point. The minted aliases land in
the file that uses them, prefixed with a `type` token because the procedure
splices bare `X = specialize T<Args>;` and after a uses clause there is no open
type section.

Three things worth knowing if you touch it:

- **"Did a round emit anything" is `at > resume`, not `TokCount > mark`.** The
  same round also REMOVES each rewritten `<Args>` group, and the two cancel
  exactly: one tuple used twice removes 8 tokens and inserts 8. The first
  version tested TokCount and the `type` keyword went missing on precisely the
  input that needed it.
- **The fixed point terminated on the wrong test, in BOTH loops.** `until
  TokCount = dgenBefore` with a comment claiming *"a round that rewrites nothing
  inserts no alias declaration, so an unchanged TokCount is exactly 'nothing
  left to collapse'"*. It is not: the same round also removes each `<Args>`
  group it rewrote, and one tuple used twice removes 8 tokens and inserts 8. The
  condition is now `(TokCount unchanged) and (insertAt unchanged)`. Fixed in the
  new loop, where it was reachable, **and in the pre-existing one in
  `ParseGenericTemplateNamed`, which has the identical shape and the identical
  disproved comment** — sibling-arm rule. Its only effect there is one extra
  round in exactly the case that was silently reading "idle"; no test moves.
- **The three uses-clause loops are now one `ParseUsesClause`.** They were
  byte-identical, the desugar has to run at all three, and a fourth copy is how
  the third site would have been the one that stayed broken.
- **`isParamForm` was NOT widened, and the attempt is worth knowing about.**
  It tests an argument only against `ti`'s own parameter names, so
  `TComparer<TKey>` inside `TDictionary<TKey, TValue>` reads as concrete and is
  minted as `IComparer$TKey`. Widening it to any template's parameter names was
  built, run, and **backed out**: it fixes neither the 15-line repro nor
  `generics.collections`, because when TCmp's sweep runs the enclosing template
  has not been parsed yet and `TKey` is nobody's known parameter. Filed
  separately as
  [[bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type]]
  with that dead end recorded, so the next holder does not spend it twice.

**A correction to this ticket's own rename.** It was re-filed from *"a generic
type parameter is unknown when a specialization is materialised cross-unit"*
with the note that the `TKey` framing *"was wrong"*. It was not wrong — it was a
**second, independent** defect (the ticket linked above), and the eleven-line
repro found a different one sitting in front of it. This ticket fixes the front
one only.

**`uses Generics.Collections` still does not compile, and cannot be closed from
here** — it stops byte-identically to `pinned` at `generics.defaults.pas:46`.
Two further walls are now filed, both pre-existing and both measured, neither
touched by this fix:

- [[bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type]]
  — the current stop, and this ticket's original `TKey` symptom.
- [[bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface]]
  — a unit specializing another unit's generic in its INTERFACE gets the
  template's method bodies streamed there. Unavoidable for collections, whose
  comparers are templates with methods.

That gate line was written before either wall was visible.

### Verification

- All five table rows match FPC 3.2.2.
- New: `test/test_delphi_generic_cross_unit.pas` (4/4) with
  `test/delphi_generic_units/`, and `test/test_generic_cross_unit_inline_specialize.pas`
  (1/1). Both oracles are FPC's. Both wired into `make test-core`.
- 14 existing generic tests run individually and 8 `.expected` files diffed
  clean; `test_generic_cycle_fail` still correctly refused;
  `test_generic_spec_per_unit` still 4/4.
- `generics.defaults.pas` still compiles alone, to the same code size.
- `generics.collections.pas` unchanged from `pinned` — same error, same line.
- `make compiler/pascal26`: `converged after 1 round(s)`.

## Log
- 2026-08-29 — resolved, commit `9a98d314c` (branch `rust`).
