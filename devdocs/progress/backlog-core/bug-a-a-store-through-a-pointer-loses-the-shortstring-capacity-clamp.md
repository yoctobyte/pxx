---
track: A
prio: 45
type: bug
status: open
created: 2026-09-02
found-by: frankA
owner: ""
summary: "HALF FIXED 2026-09-02, half open, and the two halves had DIFFERENT CAUSES — which is the correction this ticket exists to record. FIXED: `pa^[0] := <too long>` where pa points at an `array of string[N]` copied the SOURCE length and wrote past the element, on all five targets. It needed NO new carrier — SymPtrElemStrCap already holds that N and the INDEX path has read it for the element SLOT STRIDE all along; the carrier was present and the READER absent. One arm in FrozenStrElemCapOf, the one place the codebase already says this question is asked. STILL OPEN: `p^ := <too long>` where `p: ^string[8]` writes SIXTEEN chars into an eight-char buffer, past the slot, on x86-64 / i386 / aarch64 / arm32 / riscv32 alike, where FPC gives 8. That one DOES need a new carrier: the parser records the pointee KIND (LastTypePointerElemTk) and nothing records the pointee CAPACITY, and SymPtrElemStrCap means a different fact. NOT the question 058e559e9 withdrew — SymSubHi answers for the string a SYMBOL IS, and a pointer never is one. THE DEEPER POINT, worth more than either half: every clamp helper opens `if cap <= 0 then cap := DEFAULT_STR_CAP`, so a MISSING capacity is read as a PERMISSIVE one and each future missing arm is silently a buffer overrun rather than a diagnostic."
---

# A store through a pointer loses the `string[N]` capacity clamp

- **Type:** bug (IR lowering) — Track A
- **Found:** 2026-09-02, by a truncation row added to the regression test for
  `bug-a-char-into-shortstring-through-a-pointer-is-x86-64-only`. It came back
  16 where FPC says 8. That ticket's fix neither caused this nor touches it.

## Measured — six shapes, FPC 3.2.2 gives 8 on all six

| shape | FPC | pxx before | pxx now |
| --- | --- | --- | --- |
| `s := LONG` (symbol) | 8 | 8 | 8 |
| `r.s := LONG` (record field) | 8 | 8 | 8 |
| `a[0] := LONG` (array element) | 8 | 8 | 8 |
| `pr^.s := LONG` (field through a pointer) | 8 | 8 | 8 |
| `pa^[1] := LONG` (element through a pointer to array) | 8 | **16** | **8 — fixed** |
| `p^ := LONG` where `p: ^string[8]` | 8 | **16** | **16 — OPEN** |

Identical on **x86-64, i386, aarch64, arm32 and riscv32** — measured on each,
not inferred. This is not a cross-target gap; the native flagship has it too.

The overrun is real and not merely a wrong `Length`: a `string[8]` slot is
`[len][8 chars]`, and sixteen chars written into it run past the end. The fixed
row's regression test asserts the NEIGHBOUR, not just the length.

## Cause, and it is two causes

`compiler/ir.inc`'s assignment lowering derives `lhsStrCap` per LHS shape, and
`FrozenStrElemCapOf` answers for the index case. Neither had an arm for a deref.

**The `pa^[i]` half needed no new fact.** `SymPtrElemStrCap` already holds that
N — `SetPtrElemArrayInfo` fills it from `ArrTypeElemStrCap` — and
`IRLowerAddress` has read it for the element SLOT STRIDE all along, with a
comment saying why a deref node cannot carry the capacity itself. **The carrier
was present and the reader was absent**, exactly as `ASTStrElemTkOf`'s `a[i]^`
arm records for the managed-string width: *"what was missing was a reader, not a
fact."* Fixed with one arm in `FrozenStrElemCapOf`.

**The `p^` half genuinely has no carrier.** `LastTypePointerElemTk` records the
pointee's KIND and there is no `LastTypePointerStrCap` beside it, so a
`^string[8]` never captures its 8 at parse time. That is a new global plus write
sites in `AllocVar`/`AllocParam`/`AllocGlobal` and the alias path — and
`defs.inc` 5676-5723 documents the trap that comes with one at length: a
`LastType*` global a named alias fails to snapshot is read as *"whatever the
LAST unrelated type left there"*.

**Do not confuse this with the capacity question withdrawn in `058e559e9`.**
That is about `SymSubHi` serving `tyShortString` as well as `tyFixedString` —
the capacity of the string a SYMBOL IS. A pointer is not a string, which is the
same argument `SymPtrElemStrTk` had to make against `SymStrElemTk`.

## The line that turns every missing arm into an overrun

Every backend's clamp helper opens:

```pascal
if cap <= 0 then cap := DEFAULT_STR_CAP;
```

**A missing capacity is read as a permissive one.** 0 has to mean both "unset"
and a real answer and it cannot — the shape of
[[a-flag-whose-default-is-a-real-answer-cannot-say-not-applicable]]. Because the
store is the WRITE direction, the failure mode is a silent overrun rather than a
diagnostic, and that is why three of these have now been found one at a time.
**Fixing this is independent of either half above and is worth more than both.**

## The chain has grown three arms, one per discovery

`FrozenStrElemCapOf`'s own comment records the first two — the array SYMBOL arm,
added when `a[0] := s` was found writing past its element, and the array FIELD
arm, which *"was not [added], so the identical store one level in kept doing
exactly that"*. This ticket added the third. `normalise-dont-special-case.md`
says the answer at this point is **one `FrozenStrCapOfDest(astNode)` that answers
for ANY assignment target**, with every site asking it, rather than a fourth arm.

## Repro for the open half

```pascal
program mx;
type TS = string[8]; PStr = ^TS;
var s: TS; p: PStr;
begin
  s := ''; p := @s; p^ := 'abcdefghijklmnop';
  WriteLn(Length(s));    { 16 — want 8, and the write ran past the slot }
end.
```

## Gate

The six-row matrix against FPC on all five targets — the four shapes that
already pass are the ones a fix here can regress, so they are part of the test
rather than context. `test/test_shortstring_cap_through_a_pointer.pas` carries
five of the six and is wired native + i386/aarch64/arm32; the sixth row joins it
when the open half lands.

**Adjacent to [[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]**
(prio 100), which re-types `string[N]` and will touch this area. Whoever takes
the remaining half should check whether that work lands the carrier for free
before adding one.
