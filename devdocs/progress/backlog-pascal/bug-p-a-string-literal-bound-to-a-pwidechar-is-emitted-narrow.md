---
track: P
prio: 55
type: bug
blocked-by: []
status: open
owner: frankS
---

# A string literal bound to a PWideChar is emitted narrow, and only the cast surface refuses

`WideChar` is 2 bytes here and `array[0..4] of WideChar` is 10 — the CHAR side is
already right. What is wrong is the LITERAL: a string literal reaching a
`PWideChar` destination is emitted as narrow bytes, so every read through the
pointer walks two 1-byte characters as one 16-bit unit and the NUL scan runs
until it happens to meet a 2-byte zero.

Measured 2026-09-06 at compiler `d697a8a680fd`, `{$mode delphi}`, on `'abcd'`:

| surface | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `var pw: PWideChar = 'abcd'` then `Length(pw)` | **4261104** | 4 |
| `pw := 'abcd'` as a statement, then `Length(pw)` | **4261104** | 4 |
| `const pw: PWideChar = 'abcd'` | `expected 'begin' before ''abcd''` | compiles |
| `PWideChar(w)` cast | refused, naming `PXX_WIDE_PAYLOAD` | compiles |

An unbounded read of arbitrary memory, silently, on plain ASCII. `Ord(pw[0])`
answers 4 and `Ord(pw[1])` 0 against fpc's 97 and 98, so the pointer is not even
at the literal's text.

**4261104 IS NOT DATA AND MUST NOT BE READ AS A WRONG LENGTH** (frankD's
correction, and it is the right one). It is where an unbounded scan happened to
meet a 2-byte zero, so it varies with whatever is in memory. It survives
eyeballing precisely because it is a plausible integer — the same trap as a
narrowing that returns a believable value. Do not try to explain the number;
there is nothing in it to explain.

**One thing to rule out cheaply before a long hunt** (also frankD): `10e670503`
moved `NormalizeWideUnsignedLiteral` to the literal's CREATION site, so every
decimal in [2^63, 2^64) is now tagged `tyUInt64` unconditionally. If a fix here
keys off the literal's TAG rather than its text, that band will behave
differently from either side of it. Unmeasured and not a claim — a one-line
probe settles it.

## The part that matters for ranking

**`{$define PXX_WIDE_PAYLOAD}` does NOT fix it** — measured on both sides of the
gate, the answer is wild either way (4261104 / 4269344). So this is not the
payload-alias divergence wearing a new shape, and retiring that gate — the
unblock
`chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload`
proposes — would leave this exactly as it is. That chore is not this ticket's
blocker and should not be read as covering it.

## Why only one surface refuses

`pasparser_expr.inc`'s `PWideChar(...)` cast arm refuses without the define and
its comment gives the reason in the right words: *"a program that silently reads
packed byte pairs as characters is worse than both"*. That judgement is correct
and it is applied to exactly one of the four surfaces of the same construct. The
other three are the ones a program actually reaches by writing ordinary Delphi.

The const-initialiser row is a fourth shape of the ConstEval desync fixed for
var sections at `21ac9e7bc`: `InitValDestTakesStrLit` admits a `tyPointer`
destination only when its element is tyChar/tyUInt8/tyInt8 — correctly excluding
wide, since the narrow literal would be wrong — so `TryParseInitValForm` returns
False having consumed nothing, ConstEval cannot take a string either and also
consumes nothing, and the section desyncs. The refusal is right; the diagnostic
names a construct the source never got wrong.

The var-initialiser row goes the other way: that arm takes `tkString` for EVERY
destination type rather than consulting `InitValDestTakesStrLit`, which is why a
wide pointer silently gets a narrow literal there. The broad rule is deliberate
(a var keeps a wider string rule than a const) and this is the case it does not
cover.

## What a fix has to do

Emit a UTF-16 literal for a wide-pointer destination, at all three unguarded
surfaces — or, if that is deferred, refuse all three the way the cast arm does,
naming the same gap. **Refusing only some of them reproduces exactly the
condition this ticket reports.** A partial fix that leaves the statement
assignment silent is not an improvement: that is the surface real code uses.

Found chasing `tarray6.pp`, whose skip reason this corrects: that row now
COMPILES and its remaining failure is this, not the local var-section
initialisers it still names.
