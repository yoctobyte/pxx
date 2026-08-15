---
track: P
prio: 60
type: bug
blocked-by: []
summary: "The scope-hiding rule shipped 2026-08-10 (bug-p-uses-order-does-not-decide-which-unit-wins) covers ROUTINES only. Types and classes still resolve flat first-match through FindUClass, so `uses a, b` binds b's Who but a's Thing — in the SAME program. This is the sibling arm of an already-fixed rule, and it is what makes a duplicated `Exception` class order-dependent."
status: done
owner: agent-an-night
---

# Scope hiding covers routines but not types/classes

**Not a new rule — the unfixed half of one that shipped.**
[[bug-p-uses-order-does-not-decide-which-unit-wins]] implemented
[[decide-scope-hiding-vs-flat-overload-set]] on 2026-08-10 (commit `ea0e20254`):
a declaration hides a same-named one from an earlier or outer scope unless
marked `overload`, so `uses a, b` binds b's. It was built as candidate removal
in `MatchElig` plus a binding query `FindProcBound`, measured against FPC, and
gated at `--tier limited`.

**That work is sound and this ticket does not revisit it.** It only observes
that it reached PROCEDURES and not TYPES.

## Measured — both answers in ONE program

```pascal
unit ru_a;                             { ru_b identical, 'B' for 'A' }
interface
function Who: AnsiString;
type Thing = class function W: AnsiString; end;
```
```pascal
program ru_m; uses ru_a, ru_b;
var t: Thing;
begin
  WriteLn('routine: ', Who);           { ROUTINE-B  <- correct, hiding works }
  t := Thing.Create; WriteLn('class: ', t.W);   { CLASS-A  <- WRONG, want CLASS-B }
end.
```

FPC says `B` for both (verified separately with a two-unit `Thing` fixture:
FPC prints `UB`). pxx splits: the routine obeys the rule, the class does not.

## Why — two lookups, one rule applied to one of them

Routine binding goes through `MatchElig` / `FindProcBound`, which is where the
hiding candidate-removal lives. Class and type references go through
`FindUClass`, which returns the **first** row whose name matches, whatever unit
declared it. Nothing in that path knows about scopes.

`devdocs/dev/normalise-dont-special-case.md` names this exactly: *if you fix a
bug on one arm of a double case, grep for the sibling before closing the
ticket.* The sibling was types.

## Why it surfaced now

It is what makes a duplicated `Exception` class order-dependent, which is the
one residual in [[feature-a-one-exception-class-in-a-shared-unit]] — that design
gives `sysutils` and `pylib` each a class named `Exception`, and the bare name
then resolves to whichever registered first rather than to the last unit named.
Before that design there were no duplicated class names worth noticing, which is
why the gap in the 2026-08-10 fix was invisible for four months.

## Prior art that constrains the fix — READ BEFORE STARTING

[[bug-pascal-duplicate-class-name-silently-shadows]] already tried the obvious
change and **reverted it**: preferring a class whose `UClsUnitIdx` is the unit
being parsed, falling back to first-match. Read that ticket's reverted-attempt
section before writing any code.

And the harder constraint, from the routine half: **do not rank inside the
lookup.** `FindProc` returns an overload-set REPRESENTATIVE that the parser
reads signatures off and NilPy reads return types off; ranking there broke the
self-compile and segfaulted the NilPy stdlib, and **both survived
`gate.sh quick`**. `FindUClass` is likely the same shape — a representative
consumed by type inference, not only a binding query. The routine fix's answer
was a SEPARATE binding query (`FindProcBound`) leaving the representative alone;
expect to need the same here rather than a ranking tweak inside `FindUClass`.

## Scope

Classes are the case with a repro. Whether plain type aliases, records,
enumerations and constants have the same gap is **not measured** — check them
before closing, since they are separate registries and the point of this ticket
is that one arm of a rule got missed.

## Gate

`uses ru_a, ru_b` binds `ru_b`'s `Thing` and `uses ru_b, ru_a` binds `ru_a`'s,
matching FPC, with the routine half still correct in the same program. Then, per
the prior art above, **`--tier limited` at minimum** — the quick tier passed two
previously-broken versions of the routine fix, and `make test-core` is what
caught its qualified-call regression.

## Fixed 2026-08-15 — and it was FIVE tables, not one

Reproduced first, both orders, with FPC 3.2.2 as the oracle. Then measured the
Scope section's open question ("are aliases, records, enums, constants the
same?") before writing any code, and the answer was mixed — which is why the
fix is wider than `FindUClass`:

| name | before | FPC |
| --- | --- | --- |
| routine | B ✓ | B |
| **class / record** (`FindUClass`) | **A ✗** | B |
| **plain alias** (`FindTypeAlias`) | **A ✗** | B |
| **enum type** (`FindEnumType`) | **A ✗** | B |
| **named array type** (`FindArrayType`) | **A ✗** | B |
| constant / variable (`FindSym`) | B ✓ | B |

Constants were already right for an unrelated reason: `FindSym` walks a
NEWEST-first hash chain, so the later registration already won. Records were
already right too — they share `FindUClass` with classes, which is the same
defect seen from the other side.

### The fix

`UsesRankOf(curUnit, declUnit)` = the index of the LAST `uses` edge from
`curUnit` to `declUnit` (edges are appended as clauses parse, so the index IS
the clause order); `2147483647` for the scope's own unit; `-1` for a unit it
never named, so ambient/compiler-minted rows cannot outrank one the source
asked for. Each of the four lookups now keeps the best-ranked of the rows
`DeclVisible` already accepted, instead of the first. **A tie keeps the FIRST
row**, so a lone declaration, two rows from one unit, and two ambient rows all
behave exactly as before — which is what leaves pylib's and sysutils'
`Exception` merged.

### Why ranking inside the lookup is safe HERE

The ticket warns not to rank inside the lookup, from the routine half's
experience. That constraint is about `FindProc` returning an overload-set
REPRESENTATIVE the parser reads signatures off — ranking there changes which
signature comes back. A type table has no overload set: the row IS the answer,
`DeclVisible` already filters it, and the rank only orders what survived that
filter. So no separate binding query was needed, and none of the 243
`FindUClass` call sites had to move.

### Verified

- Both clause orders, seven names, **byte-identical to FPC 3.2.2** — the new
  `test/test_scope_hiding_types.pas` / `_rev.pas` over twin units
  `test/shd_unit_a.pas` / `_b.pas`, wired into `test-core`.
- The prior art's two failure modes explicitly re-checked and still correct:
  `test_nilpy_rtl_exception_surface`, `test_nilpy_pyexception_bare_vs_qualified`,
  `test_uses_order_pylib_exception_a`/`_b` (the qualified-name invariant in both
  orders), `test_nilpy_qualified_ctor`, `test_pascal_duplicate_class_fail`, and a
  program importing tkinter AND reportlab — the `Canvas` collision that got the
  first attempt reverted — which builds a PDF correctly.
- Self-host fixedpoint byte-identical; `gate.sh quick` GREEN **including the FPC
  seed canary**, which is what caught the one real slip: `UsesRankOf` is defined
  beside `VisibilityAllows` but called from the type tables above it, and FPC has
  none of pxx's declare-anywhere laxness. Forward declaration added
  (bug-a-fpc-seed-drift-emitasmx64-forward, same shape).

Per the CLAUDE.md gate rule the `--tier limited` line above is superseded:
quick + self-host is the gate, and Track T sweeps the matrix against the pushed
sha. Flagging it anyway because this ticket's own argument for limited (quick
passed two broken versions of the ROUTINE fix) is a good one — the T report for
this sha is worth reading rather than assuming.

Also closes the duplicate
[[bug-p-class-name-collision-across-units-resolves-first-not-last]] (same
divergence, filed separately by Track T on 2026-08-14), and updates
`devdocs/dev/name-resolution.md` §2.2, which said the rule was "MISSING for
types/classes".

## Log
- 2026-08-15 — resolved, commit 34e066b7e.
