---
track: P
prio: 45
type: feature
blocked-by: []
status: done
commit: 77c6dd854
summary: "Type-helper method dispatch keyed on the receiver SYMBOL, so only a plain declared variable worked. A literal, a call result, a grouped expression and a chained helper result were refused (two of them silently wrong until the same day). Self is by-reference, so a computed receiver needs an addressable home: bind it to a hidden local once."
owner: claude-A
---

# Type-helper methods on a computed receiver

The P-side half of [[feature-p-delphi-string-helpers]], split out because the
rest of that ticket is the sysutils `TStringHelper` declaration, which is
`lib/rtl` and therefore Track B file-ownership.

## What was wrong

`FindHelperForType` was consulted from exactly one place — the TYPE-HELPER
dispatch in `ParseSelectors`, guarded on `idx >= 0`, a declared symbol. So,
against fpc 3.2.2 with the same `type helper for string` in scope:

| spelling | fpc | pxx before |
| --- | --- | --- |
| `s.Twice` | `aa` | `aa` |
| `s.Twice.Twice` | `aaaa` | **24929** (`'aa'` as an Int32) |
| `s.Twice.IsEmpty` | `FALSE` | **24929** (the member silently dropped) |
| `(F).Twice` | `qq` | **113** (`ord('q')`) |
| `(s + 'x').Twice` | `axax` | IR_UNSUPPORTED |
| `'xy'.Twice` | `xyxy` | parse error at the `.` |
| `F.Twice` | `qq` | parse error at the `.` |
| `Copy(s,1,1).Twice` | `aa` | parse error at the `.` |

The three wrong-number rows were made loud first, separately, so the refusal
survives independently of the feature:
[[bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes]].

## Fix

One routine, `TypeHelperOnValue` (`pasparser_lval.inc`), asked from three
places that each already had a `.`-handling path:

1. `ParseClassRecordSelectors`, just before `RequireRecMember` — the CHAINED
   case. A helper method's return type resets `recId` to `REC_NONE` and the
   selector loop keeps running, so the second member arrives with a value
   receiver.
2. the grouped-postfix tail in `ParseFactorCore` — `(F).Twice`,
   `(s + 'x').Twice`. Asked before that tail consumes the dot, because by the
   time it knows what it is looking at the dot is gone.
3. the factor-level suffix, right after `ParseFactorCore` — a string LITERAL
   and a bare CALL RESULT, which never run through `ParseLValueAST` and so
   arrive with `CurTok` still on the `.`. Factor level is the only correct
   level: a method binds tighter than `+`, so `'a' + 'b'.Twice` is
   `'a' + ('b'.Twice)` — which both compilers in fact reject, but for the
   precedence reason, not because the parse was wrong.

A VARIABLE receiver deliberately keeps its existing path. Self is by
reference, and for a variable that means the address of the variable itself:
`s.Bang` writing `Self := Self + '!'` has to write through. Only a computed
value gets the hidden local.

**Binding is what makes the receiver evaluate once.** `F.Twice.Twice` calls F
one time, which the test asserts with a counter.

**The temp takes the HELPER'S declared target type, not the receiver's own.**
`FindHelperForType` treats frozen `tyString` and managed `tyAnsiString` as one
family on purpose, so a `helper for string` legitimately matches a string
LITERAL — whose node is `tyString`. Binding that to a `tyString` temp gave it
the frozen default capacity and `'xy'.Twice` printed NOTHING where FPC prints
`xyxy`. Since Self is by-reference, the declared target is the only type both
ends agree on anyway.

## Where pxx is now laxer than FPC

`(G + 1).Sq` on an Integer helper compiles here and FPC says `Illegal
qualifier`; FPC accepts the same shape for strings. Laxness, not a wrong
answer, and the dialect is deliberately lax by default — noted, not filed.
`7.Sq` is refused by both (`7.` lexes as a float).

## Verification

`test/test_type_helper_on_a_value.pas` (wired into `test-core`), 19 rows,
`.expected` is fpc 3.2.2's own output — matched byte for byte. Covers the
write-through variable receiver, string and Integer helpers, chained, grouped,
literal, bare-call and `Copy(...)` receivers, and the evaluation-count
assertion.

`test_chained_helper_member_fail.pas` was retargeted at a member that exists
nowhere, so the silent-read refusal survives the feature that made the valid
spelling compile.

`make compiler/pascal26` converged in one round; `tools/gate.sh quick` GREEN;
141 lib units compile; fpc-testsuite unmoved.
