---
track: P
prio: 55
type: bug
blocked-by: []
status: open
owner: frankS
---

# Routine-local name scoping is implemented in one of FIVE tables, and the one implementation is wrong at the edge

Six measured repros, one concept, five name tables. Every one is a silent
wrong value or a refused-correct-program, and none needs generics.

| table | rule today | measured |
| --- | --- | --- |
| UCls (record/class type names) | FLAT, first match wins | a SIBLING routine's local `TRec` loses to an earlier routine's — fpc `A 3 / B 1`, pxx `A 3 / B 3`. The row the title's own repro needs. |
| alias (type aliases) | FLAT, first match wins | nested routine's `TRec` ignored, binds the enclosing one — fpc 1, pxx 3 |
| set const | FLAT, first match wins | **sibling** routine's `S = [7,8]` ignored, binds the earlier routine's `S = [1,2,3]` — fpc `B FALSE TRUE`, pxx `B TRUE FALSE` |
| string const | two-tier: own routine, else global | over-corrects — a nested routine reading the ENCLOSING routine's const is **refused**: `undefined variable (Greeting)`, fpc prints it |

```pascal
procedure A; const S = [1, 2, 3]; var v: set of Byte;
begin v := S; Writeln('A ', 3 in v); end;
procedure B; const S = [7, 8]; var v: set of Byte;
begin v := S; Writeln('B ', 3 in v, ' ', 7 in v); end;   { pxx: B TRUE FALSE }
begin A; B; end.
```
```pascal
procedure Outer; const Greeting = 'from outer';
  procedure Inner; begin Writeln(Greeting); end;         { pxx: undefined variable }
begin Inner; end;
```

## This is the sibling grep that was never run

`StrConstOwner` (defs.inc) exists **for this exact bug**, one table over —
`bug-pascal-string-const-not-scoped` — and its comment describes today's alias
and set-const behaviour word for word: *"a `const S = 'x';` inside one routine
stayed visible to every routine parsed after it — and the lookup returned the
FIRST match, so the leaked one even beat a later routine's OWN const of the same
name, substituting the wrong text silently."* The rule was written once and the
other two tables were never checked. Three mechanisms for one concept is the
count `devdocs/dev/root-cause-over-microfix.md` calls a design flaw, and
`normalise-dont-special-case.md`'s "fixed one arm, grep for the sibling" is the
step that was skipped — so fixing `FindSetConst` alone would repeat it.

## Why the existing rule cannot just be copied

`FindStrConst`'s two tiers are *own routine* and *global*, with no tier for an
ENCLOSING routine — which is the third row above. There is no proc parent chain
to walk: `ParseNestedRoutine` lambda-LIFTS a nested routine into a flat
top-level one (Approach B, `PendNestTok` / `FlushPendingNestedProcs`), so by the
time `Inner` is parsed its `CurProc` is its own and the enclosing routine is
gone from the parser's state. The alias table's flat search gets that row right
BY ACCIDENT, which is why copying the "fix" onto it would trade a wrong answer
for a refusal.

The fix is one lift-parent recorded per lifted routine (the per-routine
boundaries in `PendNestRtnStart` are already the place to hang it) and ONE
`ScopeReaches(ownerProc, CurProc)` helper walking it, used by all three
lookups — and by `AliasCommit`, which is already the single chokepoint the alias
table added for exactly this class of "the rule was spelled at one call site and
missing at another".

## Not to be confused with

`bug-p-a-nested-routines-local-type-does-not-shadow-the-enclosing-routines` is
the alias row of this table, filed first and narrower; this ticket is the group.
Fix them together or the halves disagree.

Noticed in passing, not measured further: the `Greeting` refusal's diagnostic
names `./compiler/builtin/builtinheap.pas` as the file, which is not where the
error is — the token->file map does not follow a lifted routine.

---

## CORRECTION 2026-09-06: it is FIVE tables, and the title undercounts

Measured while fixing it. `UCls` is the fifth and it is the one the headline
repro actually needs: **`type TRec = record ... end` inside a routine is a UCls
row, not an alias row**, so `AliasOwnerProc` does not reach it and the two are
indistinguishable in the source. `FindUClass`'s same-unit scan took the FIRST
match, so a SIBLING routine's local `TRec` beat its own — fpc `A 3 / B 1`, pxx
`A 3 / B 3`, no nesting and no generics. `Syms` is the control: already scoped
via `FindSym`, which is what shows the rule is writable here.

**And "no proc parent chain exists, so the lift-parent must be recorded at lift
time" — written above, and false.** `ParseNestedRoutine` leaves an in-place
`<header>; forward;` behind, and that forward is parsed while `CurProc` is still
the ENCLOSING routine, so `ProcLexParent[ProcCount] := CurProc` at `RegisterProc`
— the documented single chokepoint for every `Proc*` table — is the whole
mechanism. The ticket sent a reader to the harder place because its author
reasoned about the lift instead of looking at what the lift leaves behind.

## Residual, NOT fixed here

`specialize TBox<TRec>` in a nested routine still binds the OUTER `TRec` even
though a bare `TRec` in the same body now resolves correctly. The specialization
dedup compares concrete arguments **by NAME string** (`SpecConcreteNames`), and
two different types in two scopes share the spelling — a name standing in for
the type it names, one layer above the tables this ticket is about. Its own
ticket, or the group's next rung.
