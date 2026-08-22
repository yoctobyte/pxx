---
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "`var v: Integer deprecated;` answered `unknown type: deprecated` — the var section's type loop kept calling ParseTypeKind until a stop token, and a hint directive is a plain identifier, so it was read as a second type name. Record and class fields were refused too. `type`, `const` and routine headers already worked."
---

# Hint directives are refused on a variable or a field

Found 2026-08-22 by an FPC differential sweep over less-trodden language
features (`fpc -Mobjfpc -O1` 3.2.2 vs pxx `0b9004cae`).

## The measurement

| declaration | fpc | pxx before |
| --- | --- | --- |
| `procedure Q; deprecated;` | ok | ok |
| `type T = Integer deprecated;` | ok | ok |
| `const K = 1 deprecated;` | ok | ok |
| `var v: Integer deprecated;` | ok | **`unknown type: deprecated`** |
| `var v: Integer platform;` | ok | **`unknown type: platform`** |
| `var v: Integer experimental;` | ok | **`unknown type: experimental`** |
| `var v: Integer deprecated 'use w';` | ok | **`unknown type: deprecated`** |
| `var v: Integer = 5 deprecated;` | ok | **refused** |
| `var v: Integer absolute w deprecated;` | ok | **refused** |
| `record f: Integer deprecated; end` | ok | **`Expected: :`** |
| `class f: Integer deprecated; end` | ok | **`Expected: :`** |

Half the declaration forms in the language, with an error message that names
the directive as if it were a mistyped type.

## Root cause

Two of them, and the first is the interesting one.

**The var section's type loop.** `ParseDeclTypeDesc` ends with

```pascal
while not (CurTok.Kind in [tkSemicolon, tkEq, tkBegin, ...]) and
      not ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'absolute')) do
  VDTk := ParseTypeKind;
```

— it keeps consuming type descriptors until a stop token. A hint directive is a
plain identifier, so it was handed to `ParseTypeKind` as a *second type name*,
which is where `unknown type: deprecated` comes from. `absolute` is on that stop
list for exactly this reason and has a comment saying so; hints are the same
shape and were missed. The stop list, not the skip, was the actual defect.

**Three field parsers.** The record body, the class body and the var section
each parse a declaration's tail themselves, so each needed its own
`SkipHintDirectives` call. (`type` and `const` already had theirs, which is why
those rows passed.)

## The fix

- `IsHintDirectiveName` holds the list once; `SkipHintDirectives` consumes and
  the stop-list guard tests through the same function, so the two cannot drift.
- The var-section stop list now stops at a hint directive as it already stopped
  at `absolute`.
- `SkipHintDirectives` calls added: in the var section after the type *and*
  before the terminating `;` (fpc accepts a hint before `absolute`, after it,
  and after an `= value` clause, so one position is not enough), at the end of a
  record field, and at the end of a class field.

Parse-and-ignore, matching fpc with hints off. The directive must not change
what the declaration means, so the test asserts every value rather than merely
compiling — a skip that swallowed something real would fail it.

## Verified against fpc

All five directives on a var; the `deprecated 'message'` form; a hint after an
initialiser and after an `absolute` overlay (the overlay must still be an
overlay — asserted through the target); plain declarations following hinted ones
in the same section; record fields including an array field; class fields; and
`var deprecated: Integer` still being a legal identifier, which fpc also allows.
Output byte-identical to `fpc -O1`.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_hint_directives_on_vars_and_fields.pas`, 18 assertions, wired
into `test-core`.
