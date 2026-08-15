---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`const C = 'z'; Ord(C)` answers a pointer-looking number (4287626) instead of 122. A one-character untyped const lands in the STRING const table, and Ord() on it takes the value's address rather than its code point. FPC gives 122. Pre-existing — reproduces on `pinned`."
---

# `Ord()` of a one-character untyped const answers its address

- **Type:** bug — **Track P** (Pascal frontend; the const tables live in the
  shared `symtab.inc`/`parser.inc`, so treat as A's ground for edit-collision
  purposes).
- **Found:** 2026-08-15, incidentally, while building the namespace-depth quick
  canary — the canary summed one value of every declaration KIND and its total
  disagreed with FPC.
- **Pre-existing**: reproduces on `stable_linux_amd64/default/pinned`, so it is
  not fallout of the non-transitive-uses work that found it.

## Measured

```pascal
unit u; interface const DeepChar = 'z'; implementation end.

program p; uses u;
begin writeln(Ord(DeepChar)); end.
```

| | result |
| --- | --- |
| pxx (HEAD) | `4287626` |
| pxx (`pinned`) | `4287562` |
| FPC 3.2.2 `-Mobjfpc` | `122` |

The two pxx numbers differ between builds and both sit in the data segment's
range, which is the tell: this is the string value's ADDRESS, not a computed
code point. `Length(DeepStr)` on a multi-character const in the same table is
correct, and comparison works — `if DeepChar = 'z'` is True — so it is `Ord()`
specifically, not the const table generally.

## Likely mechanism (unverified — measure before fixing)

`const C = 'z'` is untyped, so it registers in the **string** const table
(`StrConstName`/`StrConstSOff`/`StrConstSLen`, symtab.inc), not as a char. A
use builds an `AN_STR_LIT` over the literal's source span. `Ord()` presumably
lowers its argument as a value and, given a string, takes the pointer.

FPC's rule is that a single-character untyped string const is assignment- and
Ord-compatible with Char. The fix is probably at the `Ord()` lowering (a
one-character AN_STR_LIT argument means its code point), but the right question
to ask first is how many OTHER char contexts a one-char string const reaches —
`Chr`/`Ord` round-trips, `case C of`, a `set of Char` membership test, passing
it to a `Char` parameter. If more than one of those is wrong, the fix belongs
where the const is CLASSIFIED (one-char untyped const = char-compatible), not
at each consumer. That is the
`devdocs/dev/normalise-dont-special-case.md` call and worth making
deliberately: two mechanisms for one concept is a smell, three is a design flaw.

## Repro / gate

`test/usesdepth/udeep2.pas` carries the comparison form and a comment pointing
here; restore the `Ord(DeepChar)` term in `Middle` when this is fixed and the
quick canary's expected total goes back to including it directly (it already
totals 180 either way — the `if` adds the same 122).

Gate: `make compiler/pascal26` + the repro above answering 122 + `tools/gate.sh
quick`. Oracle is FPC 3.2.2 under `-Mobjfpc`.
