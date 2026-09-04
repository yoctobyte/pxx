---
slug: bug-p-a-generic-function-cannot-be-declared-in-a-unit
track: P
prio: 40
type: bug
status: done
owner:
blocked-by: []
summary: "FIXED 2026-09-04. A `generic function F<T>(...)` was accepted at PROGRAM level and refused in a UNIT in both sections, and refused again beneath a type section anywhere; an imported one could not be inline-specialized at all. Four sites: a `generic` arm in each of the two unit-section dispatchers, a type section that ends at `generic function` the way it already ends at `operator`, and SpecializeImportedGenericFuncUses on the uses clause beside the class-side desugar. All five shapes now match fpc 3.2.2. Second cost paid: ParseGenericFunctionDef's copy of the body-extent counter had no positive control and now has one -- but only from a PROGRAM-body call, because an in-unit call cancels the defect out."
---

# A `generic function` cannot be declared in a unit

## Repro

```pascal
unit ugf; {$mode objfpc}
interface
function Caller: Integer;
implementation

generic function WrapTry<T>(a: T): T;
begin
  Result := a;
  try Result := a + a; finally Result := Result + 1; end;
end;

function Caller: Integer;
begin Result := specialize WrapTry<Integer>(4); end;

end.
```

| | result |
| --- | --- |
| FPC 3.2.2 | **9** |
| pxx, in the **implementation** section (above) | `unexpected token in a unit implementation section` |
| pxx, in the **interface** section | `expected generic class name` |
| pxx, same function at **program** level | **9** — works |

Both pxx failures are present on the pinned binary and on HEAD; this is not a
regression, and the `try` inside the body is incidental — a bodyless-simple
`generic function` in a unit fails the same way.

## The second cost, which is why this is filed rather than left

`compiler/pasparser_generic.inc` has two copies of the same body-extent counter.
The method-side one (`GenericMethodBodyEnd`) was measurably wrong — it counted
only `begin`/`case`, so `try` and `asm` ended a body one `end` early — and is
fixed with a positive control against the pinned binary.

The function-side copy at `:3370` had the identical defect and was corrected in
the same change. **It has no positive control and cannot be given one**, because
the only places a short generic-function body could be mis-terminated are a
unit's two sections, and this ticket is why neither is reachable. At program
level the pre-fix binary is already correct.

So the fix there is **unverified by construction**, which is recorded at the
line and in `test/test_generic_body_end_counting.pas`. Closing this ticket makes
that arm testable; the regression test should gain the arm at the same time.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 71deb21d4.

## Fixed 2026-09-04 (frankB) — three copies of one dispatcher, and only the first had the arm

`generic` was handled at PROGRAM declaration level (`pasparser_prog.inc`) and
nowhere else. A unit's interface loop and its implementation pre-scan are the
same dispatcher written twice more (`ParseUnit`, `pasparser_proc.inc`), and both
sent `generic` to `UnitSectionStrayToken`. That is the shape
`devdocs/dev/normalise-dont-special-case.md` names: a construct reachable
through three paths, fixed on one.

Four changes, each measured against FPC 3.2.2:

1. **Unit implementation** — a `generic` arm that clears `PreScanPass` around
   `ParseGenericFunctionDef`, exactly as the program loop does.
2. **Unit interface** — the header form has no body, so it is consumed as one
   declaration by the routine that already did this for `operator` headers.
   Renamed `SkipOperatorDeclHeader` -> `SkipDeclHeaderToSemicolon`: the
   operator-only name is what made a second caller look like it needed a second
   routine.
3. **Type sections** — `generic` opens a TYPE or a ROUTINE and only the NEXT
   token says which. `generic function` beneath a type section reached
   `ParseGenericTemplate` and died as `expected generic class name`, so the fix
   above was not reachable from a real unit at all. It now ends the type section
   the same way `operator` already did (`pasparser_decl.inc`).
4. **Cross-file inline specialisation** — `specialize F<C>(...)` on an imported
   routine. Every unit's tokens are APPENDED behind the file that used it, so
   the importer's body sits BEHIND the template in `Tokens[]` while being ahead
   of it in scope; `SpecializeInlineGenericFuncUses` scans FORWARD from the
   template and never reached it. The call died as `expected ')' before 'F'` —
   a visibility problem wearing a syntax error's clothes. New
   `SpecializeImportedGenericFuncUses` sweeps at the end of `ParseUsesClause`,
   which is where the CLASS-side `DesugarImportedDelphiGenericUses` already runs
   and for the identical reason. Hooking it to the PROGRAM instead also works
   and was the first version; it leaves the unit-to-unit row broken, because
   there is no later point inside a unit from which a forward scan reaches that
   unit's own body. The uses clause is the only site where both hold.

### Measured, pxx vs fpc 3.2.2

| shape | fpc | pxx before | pxx after |
| --- | --- | --- | --- |
| `generic function` in a unit IMPLEMENTATION, used in that unit | 9 | `unexpected token in a unit implementation section` | 9 |
| header in the INTERFACE + def in the implementation | 8 | `expected generic class name` | 8 |
| same, with a `type` section above the header | 8 200 | `expected generic class name` | 8 200 |
| a UNIT inline-specialising ANOTHER unit's routine | 42 | `expected ')' before 'Twice'` | 42 |
| the PROGRAM inline-specialising a unit's routine | 8 | `expected ')' before 'WrapI'` | 8 |

### The second cost is paid: the function-side counter now has a positive control

This ticket was filed partly because `pasparser_generic.inc`'s generic-FUNCTION
copy of the body-extent counter (the `[tkBegin, tkCase, tkTry, tkAsm]` set) was
corrected alongside the measured method-side fix and was **unverifiable by
construction** — the only places a short generic-function body could be
mis-terminated were a unit's two sections, and this ticket is why neither was
reachable.

`test/test_generic_body_end_counting.pas` gains that control, and **the first
draft of it could not fail**: arms calling the generic functions from wrappers
inside the same unit PASS with the counter reverted to `[tkBegin, tkCase]`. The
truncated template ends one `end` early and the specialisation for an in-unit
use is spliced at exactly the position that leftover `end` occupies, so the two
cancel and the routine parses correctly by accident. Only a call from the
PROGRAM BODY exposes it. Verified both ways at the final tree: with the counter
reverted the unit fails to compile (`unexpected token in a unit implementation
section`, at the routine BELOW the defect); restored, `9 22 6 200` — which is
byte-for-byte what fpc 3.2.2 prints for the same four rows.

The in-unit call is kept as a labelled CONTROL rather than deleted, next to the
existing `LocalRecord` one, so the next person to add an arm here does not
rediscover the draft that could not fail.

### A fifth change, because the fix expired a written-down reason

`TemplateSrcKeyOfTok` answers "which file did this arena token come from" so a
specialization splice can keep its diagnostics pointing at the source. It
scanned two of the arena's three region kinds, and the third was left out with
the reason recorded at the code: *"a generic FUNCTION cannot be declared in a
unit interface at all today, so its body never crosses a file boundary ...
Whoever makes `generic function` work in an interface must add the third scan
with it."*

That is this change. Measured immediately after the fix: a bad expression inside
a unit's generic routine reported `pascal26:7: error: ...` with **no `in:` line
at all** — the right line of the wrong file, for a program with three lines. A
`GenericFuncSrcKey[]` parallel to `TemplateSrcKey[]` and a third scan fix it.

The comment was a correct statement about the compiler that had it, and it stayed
correct right up to the commit that made it false — which is the whole reason it
named its own expiry condition.

### Tests

- `test/test_generic_body_end_counting.pas` + `generic_bodyend_units/ugbodyend.pas`
  — the counter's positive control (second output line).
- `test/test_generic_func_in_unit.pas` + `generic_func_unit_units/` (new) — the
  five declaration and call shapes above; fpc prints `42 21 8 7` for the four
  rows it will compile (it rejects `specialize F<C> as Name;`, which is ours).
- `test/test_generic_func_error_names_its_unit_fail.pas` +
  `generic_errloc_units/uerrgfunc.pas` (new) — NEGATIVE: the file-attribution
  arm. Must not compile, and the diagnostic must carry `in: ...uerrgfunc.pas`.

Gate: `make compiler/pascal26` converged; `tools/gate.sh quick` GREEN.
