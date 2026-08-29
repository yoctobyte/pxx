---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A `property` declared inside a `type helper` is not dispatched: `s.Len` where the helper declares `property Len: SizeInt read GetLen` is refused with `a string has no members here`, while `s.GetLen` — the same accessor called directly — works. Properties on a plain record work. This blocks `s.Length`, the headline member of Delphi's TStringHelper, because FPC declares Length as a property over GetLength rather than as a method."
---

# A type helper's `property` is not dispatched, only its methods are

Found 2026-08-29 by frankB (Track B/P) while probing
[[feature-p-delphi-string-helpers]] before implementing it.

## Measured

One helper, five features, one of them missing:

| declared in a `type helper for string` | pxx |
| --- | --- |
| `function GetLen: SizeInt` — plain method | **works** |
| `function Sub(A: SizeInt): string; overload` + 2-arg sibling | **works**, both arms dispatch |
| `function Sp(const Seps: array of Char): TStringArray` — open-array param | **works** |
| returning a dynamic array | **works** |
| `property Len: SizeInt read GetLen` | **refused** |

```
pascal26:6: error: a string has no members here: pxx does not implement Delphi's
string helpers (s.Length, s.ToUpper, s.Trim, s.Substring) — ...
  near:  WriteLn  Len=  s >>>  Len
```

Delete the `property` line and call `s.GetLen` instead — the identical accessor,
same helper, same receiver — and it compiles and prints 11.

**The same construct works on a plain record.** A record with
`function GetD: Integer;` + `property D: Integer read GetD;` compiles and
`r.D` prints 42. So properties are implemented and helper dispatch is
implemented; what is missing is properties *reached through* helper dispatch.

That is the double-case shape from
`devdocs/dev/normalise-dont-special-case.md` — one construct, two paths to it,
the second one missing — and it is the second instance on this feature: the
receiver-generalisation gap recorded in `feature-p-delphi-string-helpers`
(literal, call-result and chained receivers) is the same defect on a different
axis of the same dispatch block.

## Why it matters more than one member

FPC declares `Length` on `TStringHelper` as a **property**:

```pascal
Function GetLength : SizeInt;
property Length : SizeInt read GetLength;
```

`s.Length` is the single most-used member of that surface, it is the example in
pxx's own refusal diagnostic, and it is the first thing a Delphi-2009+-style
program hits. Every other member in the ticket's scope — `ToUpper`, `ToLower`,
`Trim`, `Substring`, `IndexOf`, `StartsWith`, `Contains`, `Replace`, `Split`,
`IsEmpty`, `PadLeft`, `PadRight` — is a plain function and works today. So the
library side can deliver the whole surface **except** the one member everybody
reaches for first.

Spelling `Length` as a method instead would compile and would be wrong: it
diverges from the reference for no reason other than working around this, which
is the compiler-appeasement workaround CLAUDE.md rules out for every track. The
platonic declaration is a property.

## Where to look

`pasparser_lval.inc`, the TYPE-HELPER dispatch block — the same block the
receiver-generalisation gap names. That the two gaps sit in one block is the
argument for fixing them together rather than twice.

**Unverified.** I did not read that block; the pointer comes from
`feature-p-delphi-string-helpers`'s own measured-state section, which located
the receiver dispatch there. Treat it as a lead.

## Gate

`make compiler/pascal26` + a positive test where a helper's property is read
through a variable receiver, with the `.expected` produced by fpc under
`{$modeswitch typehelpers}`. Keep the record-property case in the same test as
the control, since it is the arm that already works and is what stops the fix
being written as a special case.
