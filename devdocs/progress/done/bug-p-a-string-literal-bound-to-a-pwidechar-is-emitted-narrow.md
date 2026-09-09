---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: frankZ
summary: "HALF (B) FIXED 2026-09-09; half (A) split out and still open. (B) `pw := 'abcd'` with `pw: PWideChar` read `4 0 0 0 25185` as UTF-16 units -- a 64-bit length of 4, then 'ab' and 'cd' NARROW, two characters per WideChar -- because TWO independent things both keyed off IsNodePChar, which does not and must not answer for a pointer to tyWideChar: the literal kept a narrow payload AND kept pointing at the block start instead of at character 0. Fixed by a separate IsNodePWideChar predicate plus a transcode; now `97 98 99 100 0`, identical to fpc, with the PChar row and the hand-built row as controls. THE WIDE CASE TAKES NO +8 AND THAT IS THE RULE, NOT AN EXCEPTION: a managed handle already points AT the data (length at [data-8]) while a literal is a static block whose address is the block START, so widening the existing +8 guard to cover both pointers -- the obvious edit -- reads `0 0 0 0 0`. Measured both ways. (A) `Length` of ANY PWideChar is a different defect, wrong for a hand-built pointer with no literal in sight, and this fix does not move it: split to bug-p-length-of-any-pwidechar-reads-a-managed-length-header with frankD's diagnosis and the do-not-widen-IsNodePChar trap intact."
---

# A string literal bound to a PWideChar is emitted narrow, and only the cast surface refuses

> ## RE-MEASURED 2026-09-09 (frankD) — THE MECHANISM BELOW IS WRONG, AND THIS IS TWO DEFECTS
>
> Compiler `21ea7825000a`, `{$mode delphi}`, against fpc 3.2.2. Everything from
> here to "## The part that matters for ranking" is the original filing and its
> reasoning does not survive; the TABLE in it is still reproducible.
>
> **(A) `Length` of a PWideChar is broken on its own, with no literal involved.**
> The discriminator is a pointer built by hand, so the literal cannot be
> implicated:
>
> ```pascal
> var buf: array[0..4] of WideChar; p: PWideChar;
> buf[0]:='a'; buf[1]:='b'; buf[2]:='c'; buf[3]:='d'; buf[4]:=#0;
> p := @buf[0];
> for i := 0 to 4 do Write(' ', Ord(p[i]));   { 97 98 99 100 0  — IDENTICAL to fpc }
> WriteLn(Length(p));                          { 4411392  where fpc says 4 }
> ```
>
> The pointer is correct, indexing through it is correct, `SizeOf(buf)` is 10.
> `Length` alone is wrong. **Every wild number in this ticket comes from here**,
> including the 4261104 the body warns not to read as data — and the warning is
> right for the wrong reason: it is not a NUL scan running until it meets a
> 2-byte zero, it is a length field read off `[p-8]`.
>
> Cause, and it is a one-armed double case: `IsNodePChar` (`ir.inc:4020`) tests
> `SymTR[].PtrBaseTk` against `tyChar`, `tyUInt8` and `tyInt8`. There is no
> `tyWideChar` arm, so `WrapPCharToString` is never applied and the operand
> reaches the runtime Length path — the one whose own comment in
> `pasparser_expr.inc` records that it "reads a [data-8] length header off the
> value" and answered 1 for an Integer.
>
> **DO NOT ADD `tyWideChar` TO THAT LIST.** `WrapPCharToString` calls
> `PCharToString`, a NARROW strlen: over UTF-16 `'abcd'` (`61 00 62 00 ...`) it
> stops at the first zero byte and answers 1. That turns an obviously-wrong
> 4411392 into a plausible 1 — the failure mode this repo names most often, and
> strictly worse than the bug. There is no `PWideCharToString` in the tree
> (checked: `lib/rtl`, `compiler/builtin`); building one is the real fix, and it
> is what makes concat, compare and WriteLn work through the same funnel rather
> than growing a Length-only second path.
>
> **(B) The literal binding lands EIGHT BYTES EARLY, on a length header.**
>
> ```
> pxx  pw as words : 4 0 0 0 25185 25699        fpc: 97 98 99 100 0 0
>      pc as bytes : 97 98 99 100 0 0 0 0       fpc: 97 98 99 100 0 0 0 0
> ```
>
> `04 00 00 00 00 00 00 00 | 61 62 63 64` — a 64-bit length of 4, then `'abcd'`
> NARROW. So the payload being narrow is real and it is the SECOND half; the
> first is that the pointer is not at the payload at all. **The `PChar` control
> is in the same program and is entirely correct**, which is what makes this
> wide-specific rather than a general literal-address problem — and that control
> is the reason the claim is a measurement and not an inference.
>
> Both binding surfaces do the same thing: `var pw: PWideChar = 'abcd'` and
> `pw := 'abcd'` both give `4 0 0 0 25185 25699`.
>
> **(A) and (B) are independently fixable and (A) does not need the payload
> model.** A ticket that fixes only (B) will still print a wild `Length`; one
> that fixes only (A) will print a correct length of a wrong string. Neither
> alone will look like progress, which is the argument for splitting the work
> and not the ticket.

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


## Resolution (2026-09-09, frankZ) — (B) fixed, (A) split, and the +8 is the interesting part

frankD's re-measurement was right on every point: two independent defects, and
the mechanism originally written in this body was wrong. (B) is fixed here; (A)
is [[bug-p-length-of-any-pwidechar-reads-a-managed-length-header]] and this fix
does not move it — measured, not assumed.

### One missing predicate, two consumers

There was no way to ask "is this node a pointer to WideChar". `IsNodePChar`
answers "does this address narrow, NUL-terminated bytes", and all ~10 of its
callers act on that by reaching for a narrow helper — so it must NOT be widened.
Both halves of (B) key off it and both therefore did nothing:

1. the literal kept its **narrow payload**, because the width transcode fires
   only for a managed-string destination;
2. the pointer kept pointing at the **block start**, because the `+8` skip that
   reaches character 0 is guarded on `IsNodePChar`.

`IsNodePWideChar` (ir.inc, identifier arm only, with the three missing arms named
in its header rather than left to be inferred) answers it, and the assignment
chain gains one transcode step before the existing skip.

### The +8 is not shared, and the obvious edit is wrong

The instinctive fix is `IsNodePChar(x) or IsNodePWideChar(x)` on the existing
`+8` guard. **That reads `0 0 0 0 0`.** Measured both ways: with the skip
applied to the transcoded value, eight bytes into a four-unit payload; without
it, `97 98 99 100 0`.

The reason is worth keeping, because it looks like an exception and is not:
**a managed handle already points AT the data** — the length lives at `[data-8]`,
which is why every runtime path reads a negative offset. A string **literal** is
not a managed handle; it is a static block whose address is the block START, so
the narrow case adds 8 to reach character 0. `PXXWideFromStr` returns a real
handle, so the skip is already paid. The two cases differ in **what the value
is**, not in how wide its characters are.

### A trigger that could not be observed until now

`pasparser_prog.inc` pulls `builtinwide` only when the program names
`widestring`, `unicodestring` or one of four PXX transcoders. `pwidechar` was
missing — and could not be noticed, because nothing ever synthesised a transcode
for a PWideChar: the literal was emitted narrow, no helper was called, and the
absent trigger had no observable. Fixing the binding makes `PXXWideFromStr`
reachable from a program naming only `PWideChar`, so without the trigger the fix
would turn a silently-wrong program into `compiler error: UTF-16 width conversion
needs builtinwide`. `widechar` is deliberately NOT a trigger: a WideChar VALUE
needs `__pxxWideCharToUTF8` from the ordinary builtin unit, and adding it would
pull 4 KB into every program that declares one.

### Controls

Both are in the committed test and both are what make the claim wide-specific:
the **PChar row** (same literal, same program, always correct — so this is not
literal addressing) and the **hand-built row** (`p := @buf[0]` over an
`array[0..4] of WideChar`, which indexed perfectly before the fix — so a wide
pointer was never broken as a pointer). All three rows equal fpc 3.2.2.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit edb2b04a9.
