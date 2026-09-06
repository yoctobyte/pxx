---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankD
created: 2026-09-06
summary: "`Free;` with no receiver inside a method — i.e. `Self.Free` — died as `undefined variable (Free)`, while `Self.Free;` two characters longer compiled and ran. The frontend has FOUR `Free` recognisers and every one of them keys on a RECEIVER (a bare symbol, an implicit-Self field, a TObject/TClass cast, a general designator via BuiltinFreeHere); a receiver-less `Free;` has none to match, fell past all four, and came out of the far end of the statement parser as a message about a VARIABLE for a call. Live case: fcl-passrc pastree.pp:2979, TPasElement.Release. FIXED 2026-09-06 — a fifth arm routed through GenMakeFreeObjectExpr (not GenMakeFreeObject, which would additionally store nil into the hidden Self PARAMETER). Cleared the wall; pastree.pp then stopped at a missing TFPList.Assign, fixed in the same commit, and now stops on a fifth wall filed separately."
---

# A receiver-less `Free;` inside a method is an undefined variable

- **Type:** bug (compat — everyday Pascal is refused) — **Track P**
  (`compiler/pasparser_stmt.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-passrc]].

## The measurement

```pascal
procedure TE.Release;
begin
  N := N - 1;
  if N = 0 then Free;        { error: undefined variable (Free) }
end;
```

`Self.Free;` in the same position compiles and prints fpc's answer. fpc 3.2.2
`-Mobjfpc` accepts both.

## Why the diagnostic points away from the cause

Four arms recognise `Free`, and each one is keyed on the shape of a
**receiver** — `obj.Free`, `FField.Free`, `TObject(x).Free`,
`L.Objects[i].Free`. There is no arm for "no receiver", so the name never
reaches any of them and lands in the ordinary assignment path, which reports
what it always reports for a name it cannot resolve. **A message about a
VARIABLE, for a call** — which is exactly why this does not read as a member of
the family it belongs to. That makes five recognisers for one concept:
`devdocs/dev/normalise-dont-special-case.md` calls two a smell and three a
design flaw, and the pressure to normalise them is real, but each arm carries a
different receiver-construction step and merging them is its own change.

## Resolution 2026-09-06

A fifth arm, before the bare-symbol `obj.Free` arm, requiring: an unresolved
name spelled `Free`, inside a method of a non-record class, statement-final
token, and no user-declared `Free`.

**Routed through `GenMakeFreeObjectExpr`, not `GenMakeFreeObject`** — the one
substantive difference from the bare-symbol arm. `GenMakeFreeObject` also emits
`obj := nil`, and the operand here is the hidden **Self parameter**. That store
is not observable in valid code (anything reading `Self` after `Free` is
already a use-after-free) but it is a write to a by-value copy the source never
asked for, and `Self` is a pure designator so the Expr form materialises no
temp and is otherwise identical.

## The fixture, and what each row was measured to prove

`test/test_a_receiverless_free_inside_a_method.pas`, wired in the Makefile,
byte-identical to fpc:

```
bare      freed=1
self      freed=2
user      freed=2 marked=1
alive     freed=2 n=1
```

**Row ownership was established by disabling the arm and rebuilding, not by
inference** — three of the four rows were already green, and a file where every
row passes for a different reason reads as one strong test.

| row | what it is |
| --- | --- |
| `bare` | the fix — does not compile at all with the arm disabled |
| `self` | `Self.Free;` **already worked**: the sibling spelling, here as a no-regression control |
| `user` | a class with its own `Free` must reach the user method — **decided by an earlier arm**, measured: unchanged with this arm's own `FindUMeth(..., 'Free') < 0` removed |
| `alive` | the UNTAKEN branch: the object must stay usable when the condition is false |

The `user` row is the honest correction here. It was written as this fix's
positive control, and the control **did not fire** when its guard was removed —
so the header says what it actually is rather than what it was meant to be. The
guard stays because every sibling arm carries it and it makes the arm correct
independently of arm order; it is belt-and-braces and this fixture does not
prove it.

## Log
- 2026-09-06 — fixed and resolved; see the commit carrying this file.
