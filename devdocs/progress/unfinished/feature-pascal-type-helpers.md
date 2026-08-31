---
track: A
prio: 55
type: feature
blocked-by: []
summary: "record/type/class helpers. v1-v3 landed and pinned: decl + impl-side Self fork + dispatch, statics/consts, `type helper for` spelling, TARGET-type-name receivers (UInt32.GetSignMask), class helpers, typed class consts. ARRAY-ELEMENT receivers landed 2026-08-31 as part of bug-p-a-member-on-an-array-element-silently-reads-the-elements-own-bytes. REMAINING: exactly one item - a STRING-LITERAL receiver ('abc'.ToLower), which fails in the LEXER/factor path (`expected ')' before '.'`), not in the helper machinery. Every other rvalue shape probed already works."
status: unfinished
owner: frankS
---

# `record helper for T` / `type helper for T` — type helpers

- **Type:** feature (Pascal frontend — Track P; dispatch plumbing may touch shared parser = A gate)
- **Status:** working
- **Owner:** frankS
- **Blocks:** [[feature-pascal-corpus-generics]] (generics.helpers.pas is in
  Generics.Collections' uses chain), and broadly sysutils.TStringHelper-style
  code across the FPC/Delphi ecosystem.

## Surface needed by generics.helpers (v1 slice)
```pascal
TValueAnsiStringHelper = record helper for AnsiString
  function ToLower: AnsiString; inline;         { Self = the string value }
end;
TValueUInt32Helper = record helper for UInt32
  class function GetSignMask: UInt32; static; inline;
  const SIZED_SIGN_MASK: array[1..32] of UInt32 = (...);
end;
```
Consumers: `ALeft.ToLower` (const string params — lvalue receivers), and
type-name statics `UInt32.GetSignMask` / `UInt32.SIZED_SIGN_MASK[i]` inside
the helpers unit itself.

## Design sketch
1. Type-section parse: `= record|type helper for <type>` → register a class-like
   entry with HelperTargetTk/Rec; members parse via the existing class member
   machinery. Self (param 0) is the TARGET type BY REFERENCE, not tyClass.
2. Impl headers `function THelper.M...` — the Self injection must fork on the
   helper marker (both decl and impl sides must agree, see b321's lesson).
3. Dispatch: member access on a NON-class receiver consults a helper registry
   (target tk+rec → newest helper ci; FPC: last visible helper wins), binds the
   method, passes @receiver as Self. Lvalue receivers first; rvalue receivers
   need a materialized temp (later).
4. Type-name receivers for statics/consts.

## Gate
make test + self-host byte-identical (shared parser); fpjson suite stays green.

## v1 LANDED 2026-07-14 (b331)
Decl (`record helper for <type>` via the advanced-record machinery, helper
marker in UClsHelperTk/Rec), impl-side Self fork, and call dispatch (early
ParseLValueAST intercept → ParseClassRecordSelectors with the helper as rec id;
Self = receiver by reference). Instance methods on variables/params work, incl.
Self mutation and const-string params; last-visible-helper-wins; frozen+managed
strings are one family. Pinned: test/test_record_helper_for_string_b331.pas.

## Remaining (v2+)
- statics + consts INSIDE helpers, and type-name receivers (UInt32.GetSignMask,
  UInt32.SIZED_SIGN_MASK[i]) — generics.helpers' UInt32/UInt64 sections.
- rvalue receivers ('abc'.ToLower, F().ToLower) — need a materialized temp.
- `type helper for` spelling; class helpers.
- generics.defaults then adds the REAL walls: methods NAMED after type keywords
  (class function Integer(constref...)), untyped constref params.

## v2 LANDED (same commit series): helper STATICS + consts
`class function ...; static;` in a helper: Self = target BY VALUE (a dummy —
static bodies may not read Self, per FPC), marked UMthIsStatic, callable both
through a VALUE (c.GetSignMask) and through the HELPER's name
(TU32Helper.GetSignMask — both the record-factory factor path and the
class-name selector path fork on the helper marker and pass a literal-0 Self).
Consts in helper bodies were already global-scoped and work. Remaining:
TARGET-type-name receivers (UInt32.GetSignMask), rvalue receivers, class
helpers — and generics.defaults' methods NAMED after type keywords
(class function Integer(constref ...)), which is the next real wall.

## v3 slice landed 2026-07-18 (a379d016): `type helper for` spelling
`type helper for T` now parses as an alias of `record helper for T` (parser type
-section dispatch, mirrors the record-helper branch; self-host byte-identical).
Instance methods + statics dispatch through the existing helper machinery. Test:
test_type_helper_for_spelling.pas. **Remaining v3:** target-type-name receivers
(`UInt32.GetSignMask`, `UInt32.SIZED_SIGN_MASK[i]`), rvalue receivers (`'abc'.ToLower`,
`F().ToLower` — need a materialized temp), class helpers.

## v3 slice landed 2026-08-20: TARGET-TYPE-NAME receivers

`UInt32.GetSignMask` — the spelling `generics.helpers` uses for its UInt32/
UInt64 sections. Before this the type's own name is not a class, so
`FindUClass` missed and it was `undefined variable (UInt32)`.

**Not a second dispatch path.** The type name resolves to the HELPER's `ci`,
which makes it the exact spelling that already worked
(`TU32Helper.GetSignMask`), so the whole static / class-var / class-const block
below it serves the new spelling unchanged — including the `UClsIsRecord[ci]`
arm that passes a by-value dummy Self, because a helper has no metaclass. One
resolver, two spellings (`normalise-dont-special-case.md`).

Guarded three ways so no other `.` path can be caught: a dot must follow (a
BARE `UInt32` must stay a type name and not become a class reference — asserted
in the test via `SizeOf(UInt32)` and an ordinary UInt32 variable in the same
program), the name must denote a type, and that type must actually have a
helper in scope. A member that then does not exist still gets the ordinary
"class method not found", which names the helper — strictly more informative
than "undefined variable".

Resolves through `BuiltinTypeNameTk` (the one builtin-name table) and then the
alias table, so all four spellings reach one helper: the builtin name
(`UInt32`), an alternative builtin spelling of the same type (`Cardinal`), a
named alias (`TMyInt = LongWord`), and a string helper (`AnsiString.Tag`).
Statics and scalar/string consts both work through it.

Test: `test/test_type_helper_typename_receiver.pas`. FPC 3.2.2 (with
`{$modeswitch typehelpers}`) answers 2147483648 for `UInt32.GetSignMask`.

**Dialect note found while building the oracle:** FPC *rejects* the helper-NAME
spelling `TU32Helper.GetSignMask` ("Objective-C categories and Object Pascal
class helpers cannot be used as types"), which pxx has accepted since v2. That
is deliberate laxness in pxx's direction, not a parity bug — but it is worth
knowing that the two spellings are not equally portable.

### v3 remaining, and one thing that turned out to be a different bug

So v3 now has exactly two items left:

- **rvalue receivers** — `'abc'.ToLower`, `F().ToLower`. Need a materialized
  temp. FPC oracle for both: `Abc` in the probe used here. Still refused.
- ~~**class helpers** (`class helper for TSomeClass`)~~ — **DONE 2026-08-27**,
  under [[compat-pascal-class-helpers]]. Same helper row, marker
  `UClsHelperTk = Ord(tyClass)`; what forked was Self (by VALUE for a class
  target, and its `RecName` is the EXTENDED class so `Self.Field` resolves) and
  the two name-lookup directions, `ClassHelperRecFor` (qualified) and
  `SelfMemberCi` (unqualified). All three `class-helper-*` probe rows are
  untagged. `test/test_class_helper_for_a_class.pas`.
- ~~**`UInt32.SIZED_SIGN_MASK[i]`**~~ — **DONE 2026-08-20, and not by helper
  code.** It fails identically
  through the HELPER's own name (`TU32Helper.SIZED_SIGN_MASK[2]`), so the
  type-name work above is not what is missing. A TYPED class const
  (`const X: T = ...`) never enters the ClassConst registry at all — the code
  says so itself: *"Only the untyped forms below are scoped; typed class consts
  have real storage and stay global."* Under that is a silent wrong-value bug
  filed separately at prio 65 as
  [[bug-p-two-classes-typed-consts-of-the-same-name-collide]]: two classes each
  declaring `const TAG: array[1..2] of Integer` share one global slot, and
  `TA.Get` returns TB's value where FPC returns TA's. Fixing that ticket makes
  `UInt32.SIZED_SIGN_MASK[i]` work for free, because it routes through the same
  registry the type-name receiver already uses. So this ticket did NOT grow a
  typed-const path of its own — fixing that bug made all three spellings
  (helper name, target-type name, in-body) work at once.
  `test/test_type_helper_const_array.pas`.


---

## 2026-08-31 — the remaining item is ONE shape, and it is not where the ticket said

The ticket's last line has read *"rvalue receivers — `'abc'.ToLower`,
`F().ToLower` — need a materialized temp. Still refused."* since v3. **Probed
rather than believed, and most of it is already done:**

| receiver | result |
| --- | --- |
| `F.Twice` | works |
| `F().Twice` | works |
| `(s + 'x').Twice` | works |
| `a[0].Twice` (array element) | **was a WRONG ANSWER**, fixed today |
| `5.Dbl` (integer literal) | works |
| `(n + 1).Dbl` (parenthesised int expr) | refused |
| `'b'.Twice` (string literal) | refused |

`TypeHelperOnValue` (the materialise-into-a-temp path) already exists and serves
the call-result and grouped-expression cases; the ticket was written before it
landed and never re-read against the code.

So the remaining work is **two refusals, not a category**, and the string-literal
one does not fail in the helper machinery at all: `'b'.Twice` dies with
`expected ')' before '.'`, i.e. the factor parser finishes a string literal and
never offers the `.` to anything. That is a different fix from `(n + 1).Dbl`,
which reaches the member path and is told *"this value has no members"*.

**The array-element case turned out to be a separate BUG, not this feature**, and
a silent wrong-answer one:
[[bug-p-a-member-on-an-array-element-silently-reads-the-elements-own-bytes]]
(fixed, with the FPC oracle). Fixing it made `a[0].Twice` work as a side effect,
because the same guard had to choose between the valid reading and the invalid
one. An lvalue receiver was never on this ticket's list, which is why nobody had
looked.
