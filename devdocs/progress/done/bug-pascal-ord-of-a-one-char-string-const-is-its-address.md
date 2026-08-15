---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`const C = 'z'; Ord(C)` answers a pointer-looking number (4287626) instead of 122. A one-character untyped const lands in the STRING const table, and Ord() on it takes the value's address rather than its code point. FPC gives 122. Pre-existing — reproduces on `pinned`."
status: done
owner: agent-an-night
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

## Fixed 2026-08-15 — at the CLASSIFICATION, because six consumers were wrong

The ticket asked the right question first ("how many OTHER char contexts does a
one-char string const reach?") and the answer settles the design call. Measured
against FPC 3.2.2 before touching anything:

| context | pxx was | FPC |
| --- | --- | --- |
| `Ord(C)` | `4288109` (an address) | `122` |
| `c := C` | a byte of that address | `z` |
| `Chr(Ord(C))` | likewise | `z` |
| `C in ['a','z']` | `FALSE` | `TRUE` |
| `Ord(Succ(C))` | an address | `123` |
| `case C of 'z'` | correct | correct |
| `C = 'z'` | correct | correct |

Six wrong, two right. So the fix is **not** at `Ord()` — it is where the const
is classified: **a one-character untyped const is registered as a `Char`**,
which is what FPC types it as, instead of going into the string const table.
That is the `normalise-dont-special-case.md` call the ticket asked to be made
deliberately; patching `Ord()` would have left the other five.

### Two more defects the reclassification exposed, both fixed here

1. **`Length()` of a Char answered the CODE POINT.** `c := 'x'; Length(c)` gave
   `120` while `Length('y')` on a literal gave `1` — latent for as long as
   chars have existed, and nothing to do with consts. Once `const Sep = '/'`
   became a Char, `Length(Sep)` SEGFAULTED rather than merely lying, which is
   how it surfaced. Folded to 1 in the parser, so every target gets it.
2. **A char const as an operand of a CONST concatenation.** `const Sep = '/';
   Joined = Sep + 'x';` no longer matched the string-const concatenator's entry
   test, fell through to the integer `ConstEval` path and produced garbage
   (`167`). `CharConstSymOf` (skConst AND tyChar, deliberately narrow) now lets
   that operand in — this is exactly blcksock's `CRLF = CR + LF` shape, so it
   was not hypothetical.

### Verified

`test/test_one_char_const_is_a_char.pas` + `.expected` in `test-core`: 20 rows
covering all six broken contexts, the two that already worked (so a fix cannot
trade them away), `Length` of a char const / char VARIABLE / char literal, and
the string contexts a Char converts into — assignment to AnsiString, both
concatenation orders, a string parameter, a char parameter, `Pos`, and the
`Empty` / `Multi` / `Joined` consts that must keep their string typing.
**Byte-identical to FPC 3.2.2 on every row.**

`test/usesdepth/udeep2.pas` restored to `Ord(DeepChar)` as this ticket asked;
the canary still totals 180 (the comparison form it replaces added the same
122), so `quick_canary_uses` is unmoved.

Self-host fixedpoint byte-identical — which is a real signal here, because the
compiler's own sources are full of one-character consts. `gate.sh quick` GREEN
with the FPC seed canary; `test_set_of_char_const`, the for-in literal-sources
test, the qualified-units test, the tkinter facade, sqlite CRUD, the Cython
module and tkinter+configparser all still build. The corpora go to Track T with
the pushed sha — this is a dialect change wide enough to want that sweep.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
