---
slug: bug-p-a-named-dynamic-array-default-declared-in-a-class-body-is-lost-if-the-implementation-omits-it
track: P
type: bug
prio: 35
status: done
created: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
title: "A class method's `= nil` default on a named dynamic-array parameter is dropped when only the declaration carries it"
summary: "CLOSED 86fb12e4c, AND THE UNVERIFIED GUESS IN THIS TICKET WAS RIGHT. MEASURED 2026-09-06 at d754eeef1: `TC = class procedure M(const a: TArr = nil); end;` with `TArr = array of Integer`, implemented as `procedure TC.M(const a: TArr);` -- the default on the DECLARATION only, which is the ordinary Pascal spelling -- made `o.M` fail with `wrong number of parameters in call to TC.M` where fpc prints `M len=0`. Four controls each removed a different explanation: an Integer default and a string default with the same omission on the same class were honoured, the same `TArr = nil` written on BOTH sides worked, and the free-routine spelling worked -- so it was never class methods, nor nil, nor the declaration-only spelling, nor the type alone. THE CAUSE IS THE ONE THIS TICKET GUESSED AND LABELLED UNVERIFIED: the declaration row recorded the ELEMENT kind because the four method parameter parsers knew only the literal `array of` spelling and ParseTypeKind collapses a named array type, while the implementation row (ParseSubroutine) recorded the array -- two rows disagreeing about one parameter, and the binding dropped the default with it. FIXED BY SOMETHING ELSE: teaching those parsers named array types for bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults made the rows agree and this row started passing, with no work aimed at it. AND THAT FIX SHIPPED A REGRESSION THIS TICKET NOW CARRIES THE CONTROL FOR: the open-array-default refusal asks its caller `is this an open array`, and the three method parsers answered with their IsArray flag because it used to be true ONLY for the literal spelling -- so the moment a named array type also set it, `const a: TArr = nil` in a class body was REFUSED as an open-array default. Shipped in d51037cf2 and caught by running the fixture BY HAND: these rows live in test-core and gate.sh quick does not run them, so GREEN was true and about the 33 unit tests. The three parsers now ask `IsArray and (dynDepth <= 0)`, which is what ParseSubroutine has always asked. Eight rows in one file, all four parsers declaration-only; the proc-type row could not be written because a procedural type cannot express a default at all (filed separately) and the file says so rather than dropping it silently."
---

# A declaration-only `= nil` default on a dynamic-array parameter is lost

```pascal
type
  TArr = array of Integer;
  TC = class
    procedure M(const a: TArr = nil);   { default HERE only }
  end;
procedure TC.M(const a: TArr);          { implementation does not repeat it }
begin WriteLn('M len=', Length(a)); end;
...
o.M;
```

| row | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `o.M` (default on the declaration only) | `error: wrong number of parameters in call to TC.M` | `M len=0` |
| `n: Integer = 5`, declaration only, same class | works | works |
| `const s: AnsiString = 'hi'`, declaration only | works | works |
| `const a: TArr = nil` written on **both** sides | works | works |
| the same shape as a **free routine** | works | works |

Four controls, and each removes a different explanation: it is not class
methods, not `nil`, not the declaration-only spelling, and not the type on its
own.

## Done when

Row 1 prints `M len=0`, with the four controls kept beside it in one file — the
value is plausible in every row, so only the rows' disagreement carries the
finding.

Found while closing
[[bug-p-a-default-value-is-accepted-on-an-open-array-parameter]], whose positive
control writes the default on both sides for exactly this reason and says so.

## How it was actually closed

Nobody worked on this ticket. It was fixed by
[[bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults]],
whose fix taught all four method parameter parsers about named array types —
which is precisely the disagreement this ticket's summary guessed at and marked
unverified. The declaration row and the implementation row now record the same
parameter, and the default binds.

**The guess being right is not why it is closed; the measurement is.** The row
prints `M len=0` and the four controls still print their own values, which is
what the "Done when" asked for.

## The regression that came with it, and the instrument that did not see it

Making `IsArray` true for a named array type broke the sibling refusal. The
open-array-default guard asks its CALLER "is this an open array", because
`IsArray` alone is the wrong half of the type — that is the whole point of
`test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas`. The
three method parsers were passing the bare flag, correctly, while it could only
mean the literal spelling. It now also means a named array, so they pass
`IsArray and (dynDepth <= 0)`, matching `ParseSubroutine`.

**`gate.sh quick` was GREEN for that commit and was not wrong.** These rows live
in `test-core`, which the gate does not run and the full-suite hook denies. GREEN
was a true statement about 33 unit tests.

**And "invisible to the per-fix loop" is what I concluded, and it is wrong.**
There is a sanctioned one-case runner and the full-suite hook's own refusal text
names it:

```
tools/testmgr.py --tier native --job src:test/<file>.pas      # ~1s, one case
```

`--job <literal>` (no glob) is allowed at any tier — it is the repro line
auto-filed regression tickets already print. Measured 2026-09-06: the row above
runs in 0.5s against a compiler snapshot at the current sha. **So the row was
not unreachable, it was unrun**, and the reason it was unrun is that I believed
`gate.sh quick` and `make test-core` were the only two things that existed. Run
it after any change to a parser your rows exercise; it costs a second and it is
the difference between a GREEN that covers your assertion and one that does
not.

## Log
- 2026-09-06 — closed by another ticket's fix, with its own regression control
  added; resolved, commit 86fb12e4c.
