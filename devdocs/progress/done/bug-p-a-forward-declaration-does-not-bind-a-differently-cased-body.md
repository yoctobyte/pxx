---
slug: bug-p-a-forward-declaration-does-not-bind-a-differently-cased-body
track: P
prio: 65
type: bug
status: done
blocked-by: []
summary: "Pascal is case-insensitive, so `function Bar; forward;` and a body written `function bar;` are ONE routine — FPC binds them, pxx did not. `FindProcOverloadRec` (symtab.inc:7311) compared `Procs[i].Name = name` with no CaseEqual arm, so the body registered a SECOND proc and the declared one stayed bodiless. Symptom depends on how the name is later reached: a direct call says `unresolved forward: Bar`, while `@Bar` captured in a TYPED CONST survives to LINK and dies as 'the address of a routine with no body was taken', accusing the address-of rather than the case mismatch. Found via the rtl-generics corpus (`TEquals.&Class` declared, `TEquals.&class` implemented) — the `&` escape is incidental. Fix: the same `(Name = name) or ((not ProcCaseSensitive[i]) and CaseEqual(...))` pair the file's four other lookups already carry; ProcCaseSensitive keeps NilPy and C case-sensitive."
owner: frankA
---

# A forward declaration does not bind a differently-cased body

Found 2026-08-29 by frankA while re-measuring
[[feature-pascal-corpus-expansion]] after walls 6 and 7 closed.

## Repro — three shapes, one defect

```pascal
{$MODE DELPHI}
program b;
type TR = record F: Pointer; end;
function Bar(a: Integer): Boolean; forward;
function bar(a: Integer): Boolean;          { body in a DIFFERENT case }
begin Result := a > 0; end;
const V: TR = (F: @Bar);
begin WriteLn(V.F <> nil); end.
```

| shape | pxx before | fpc |
| --- | --- | --- |
| direct call `Bar(1)` | `error: unresolved forward: Bar` | TRUE |
| `@Bar` in a **typed const** | `error: @Bar: the address of a routine with no body was taken` | TRUE |
| `@Bar` in a **statement** | worked | TRUE |
| matching case (control) | worked | TRUE |

## Cause

`FindProcOverloadRec` — the declaration-time matcher that decides whether a body
REUSES an existing proc entry or registers a new one — compared names exactly:

```pascal
if (ProcUnitIdx[i] = CurrentUnitIdx) and (Procs[i].Name = name) then
```

Every other proc lookup in `symtab.inc` carries the pair
`(Procs[i].Name = name) or ((not ProcCaseSensitive[i]) and CaseEqual(...))` —
four sites (3618, 9108, 9127, 9144). This one had only the exact half, so it is
the **one arm of a double case that was never fixed** — the shape
`devdocs/dev/normalise-dont-special-case.md` is about.

The hash chain was never the problem and the fix does not touch it:
`NameFoldHash` already folds A..Z, and `ProcChainHead`'s own comment says the
chain holds every proc with the same FOLDED name and that *"callers still do
their own exact/CaseEqual compare"*. Both spellings were always in the same
bucket; only this compare rejected them.

`ProcCaseSensitive` is what keeps this scoped: NilPy and C routines set it True,
so `foo` and `Foo` remain two routines there, which those languages require.

## Why it was expensive to find, and worth recording

**The diagnostic accuses the wrong construct, and which wrong construct depends
on the reference.** The corpus failure was
`@TEquals.Class: the address of a routine with no body was taken` — an ELF-writer
error, pointing at address-taking, in a unit whose declaration is
`&Class` and whose body is `&class`. The natural first hypotheses, both wrong
and both cheap to test:

1. *the `&` escape is case-sensitive* — refuted: escaped-with-matching-case
   works, and **unescaped-with-mismatched-case fails**, so `&` is irrelevant;
2. *the const path resolves methods differently from the expression path* —
   refuted: both call `FindUMeth` then `UMthProc_[mi]`, and moving the const
   after the body changes nothing.

What actually distinguishes the working statement case from the failing const
case is not the const at all — it is that the statement form in the corpus-like
shapes reached a proc that had been re-bound, while the const captured the
declaration. Dropping the class entirely and using a plain `forward` routine
produced `unresolved forward: Bar`, which names the defect outright. **The
minimal repro was the measurement that mattered; every hypothesis formed from
the corpus error was wrong.**

## Fix

`compiler/symtab.inc` — `FindProcOverloadRec` gains the CaseEqual arm. Six
lines plus the comment. No lexer change, no backend, no IR.

## Verification

- `test/test_forward_decl_case_insensitive.pas`, expectation derived from
  **FPC** and matching pxx on all 6 lines. It **fails to compile on `pinned`**
  with `unresolved forward: Bar` — the ticket's own symptom — so it
  discriminates rather than agreeing with the build that produced it.
  Covers: the plain forward routine, a class method, an ESCAPED (`&Class`)
  method, a matching-case control, the const-captured address, and the
  statement-level `@` that always worked (so a fix cannot trade one arm for the
  other).
- A class method is asserted by ADDRESS, not called through a plain function
  pointer: a class method carries a hidden Self, so invoking one through
  `function(a: Integer): Boolean` puts the argument in the Self slot and is
  undefined — **measured, FPC answers TRUE for a call that should be FALSE**.
  The corpus takes these addresses but calls them through a hand-built VMT with
  the right convention. Behaviour is checked by calling the methods normally.
- `make compiler/pascal26`: `converged after 1 round(s)`. The compiler's own
  source is full of forward declarations, so self-host is a real signal here,
  and its build emits **zero** `duplicate definition` warnings — the change
  merges nothing that was meant to stay separate.
- `tools/gate.sh quick`.

## Corpus effect — this is what it was found for

`generics.defaults.pas` (3,358 lines) **now compiles END TO END**. It was
blocked at the first `@TEquals.&Class` in the VMT const table; before this
session it had never got past its own declaration section's const block.

`generics.collections.pas` advances to a new and unrelated wall:
`unknown type: TKey` at `generics.defaults.pas:790` — a generic type parameter
out of scope. Recorded on the umbrella as the next rung; not this ticket.
