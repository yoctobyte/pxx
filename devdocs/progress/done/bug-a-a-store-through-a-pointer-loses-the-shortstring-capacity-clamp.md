---
track: A
prio: 45
type: bug
status: done
created: 2026-09-02
found-by: frankA
owner: frankA
summary: "FIXED, both halves. `p^ := <too long>` on a `^string[N]` wrote the
  SOURCE length -- sixteen characters into an eight-character slot, past the
  slot and over the NEIGHBOUR's length prefix (a `g` holding 'GUARD' came back
  EMPTY in the default mode), on x86-64/i386/aarch64/arm32/riscv32 in both
  modes: ten cells. It needed a carrier, and now shares SymPtrElemStrCap with
  the pointer-to-array case rather than growing a third convention -- via
  LastTypePointerStrCap at the one general `^T` arm, AliasPtrStrCap at alias
  registration, and SetPtrElemArrayInfo, the one procedure all four allocators
  call. Reader is FrozenStrCapOfDeref. Ten cells green, FPC byte-identical on
  all seven test rows, and the pre-fix compiler fails the new row for the right
  reason. STILL OPEN AND SEPARATE: AllocVar and AllocParam leave a plain frozen
  `string` at SymStrCap 0 on purpose, so the eleven `if cap <= 0 then cap :=
  DEFAULT_STR_CAP` sites cannot tell `255 is correct` from `the N was lost` --
  the fix there is TWO writers, not eleven readers, and it is a behaviour change
  wanting its own control."
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

**A missing capacity is read as a permissive one.** 0 has to mean both "unset"
and a real answer and it cannot — the shape of
[[a-flag-whose-default-is-a-real-answer-cannot-say-not-applicable]]. Because the
store is the WRITE direction, the failure mode is a silent overrun rather than a
diagnostic, and that is why three of these have now been found one at a time.
**Fixing this is independent of either half above and is worth more than both.**

Counted 2026-09-02, by listing the matches rather than counting them —
`if cap <= 0 then cap := DEFAULT_STR_CAP` (or `fStrCap`), **11 sites**:

| where | sites |
| --- | --- |
| backend clamp helpers | 7 — `ir_codegen.inc`, i386, aarch64, arm32, riscv32, xtensa, wasm32 |
| `pasparser_decl.inc` | 3 |
| `symtab.inc:3636` (`FrozenStrSlotSize`) | 1 |

Eleven places each deciding independently that absence means 255. `DEFAULT_STR_CAP
= 255`, so the substituted slot is 263 and aligns to **264** — the number in
frankb-a9's record-field finding the same morning, which is one instance of this
mechanism rather than a separate defect.

### The twelfth match is not a site, and it is the model

A grep also hits `symtab.inc:3657`, which is **prose inside a different
function**, and reading it is what makes the finding actionable rather than a
call for a blanket change. `SizeOfSlot` does the OPPOSITE of the eleven:

```pascal
if TypeIsFrozenString(tk) and (cap > 0) then Result := FrozenStrSlotSize(tk, cap)
else                                         Result := TypeSlotSize(tk);
```

It treats `cap <= 0` as **"none was recorded"** and declines to guess, and its
comment says why: *"Its true size is not knowable from the kind plus a zero, so
widening it here would be a guess dressed as a fix."*

So `SizeOfSlot` is not an exception to this ticket — **it is the counterexample
that proves it, and the shape the other eleven should be measured against.** One
site already distinguishes "unset" from a real answer; eleven do not. That is a
much narrower and safer job than changing eleven defaults, because it is the
same edit eleven times against a model that already exists in the tree.

**Do not read this as "change all eleven".** Each has to be asked what its
caller can actually know — the point is that today not one of them can even
express the difference.

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

## 2026-09-03 — the open half re-measured, and the ELEVEN-SITES finding is corrected

**The open half still reproduces at HEAD, on every target, in both modes.**
`p: ^string[8]`, `p^ := 'abcdefghijklmnop'`:

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| x86-64, i386, aarch64, arm32, riscv32 | len 16 | len 16 |

Ten cells, all red, and **the overrun is visible in a neighbour rather than
inferred**: a `g: TS` holding `'GUARD'` prints EMPTY in the default mode (its
8-byte length prefix clobbered) and, under `-dPXX_SHORTSTRING`, prints hundreds
of bytes of adjacent memory.

### The eleven sites do NOT want `SizeOfSlot`'s treatment, and this ticket said they did

The claim above — eleven places "each deciding independently that absence means
255", with `SizeOfSlot` as the model that declines to guess — is half wrong, and
the half that is wrong is the actionable half.

**`0` is not absence at those sites. It is a DELIBERATE encoding written one
level up, and it is CORRECT.** `symtab.inc`'s `AllocVar` (4706) and `AllocParam`
(5008) both spell:

```pascal
if TypeIsFrozenString(tk) and (tk <> tyString) then
  SymStrCap[SymCount] := LastTypeStrCap;
```

so a plain frozen `string` is left at 0 ON PURPOSE, and the `cap <= 0 then cap
:= DEFAULT_STR_CAP` downstream is what gives it its capacity. Measured rather
than read off the guard: under `-uPXX_MANAGED_STRING` (the frozen model, the
self-host build), `var s: string` with a 300-character store comes back
**Length 255 with the neighbour intact** — the substitution is doing real work
and 255 is that type's real capacity.

So the eleven readers cannot tell "plain frozen string, 255 is right" from
"`string[N]` whose N was lost", because **the WRITER chose the same encoding for
both.** Making them decline would break every plain frozen string. This is
[[a-flag-whose-default-is-a-real-answer-cannot-say-not-applicable]] exactly:
membership needs its own bit, and here the bit exists — it is the destination
KIND, which is what `SizeOfSlot` actually keys on (`TypeIsFrozenString(tk) and
(cap > 0)`, falling back to `TypeSlotSize(tk)`), not on the zero.

### Which moves the fix from eleven readers to two writers

Give a plain frozen `string` its real `DEFAULT_STR_CAP` at allocation. Then `0`
means *unset* everywhere downstream, the eleven substitutions become dead for
every legitimate case, and each can become a diagnostic instead of an overrun —
which is the outcome this ticket wanted. **Two sites, not eleven**
([[a-count-that-grows-under-enumeration-means-the-fix-is-in-the-wrong-place]]:
guard the few writes, not the many reads), plus `pasparser_proc.inc:2177`, which
already guards on `> 0` and needs no change.

Not landed with the store fix below, and the reason I first gave for parking it
was WRONG in a way worth keeping. I read `owner: frankB` on
`feature-p-implement-the-real-tyshortstring-byte-prefix-layout` (prio 100,
`working/`) as naming a session and parked on "wait for its work to land the
carrier". **`owner:` there names the CHECKOUT, not a session** — frankb-78 is
not doing that work, nobody is, and P4 is unreleased and the owner's alone. So
the wait would have been indefinite. That is the third time in one day that
per-checkout state was read as a property of something else on this box (the
C-conformance corpus twice, this once); the tell each time is that the answer
came from asking, and cost one message.

**A note on how the two writer sites were found:** by an edit that ASSERTED its
match was unique and failed, not by reading. The guard appears twice with
identical text, in `AllocVar` and `AllocParam` — the double case
`normalise-dont-special-case.md` is about, and a `replace` without the assert
would have fixed one arm and left the other.

## 2026-09-03, later — the open half is FIXED

Ten cells red became ten cells green, and FPC agrees byte-for-byte on all seven
rows of the regression test.

**It needed a carrier and it now has one, in the slot that already existed.**
frankb-78's steer, taken: rather than a third convention for "the N behind a
pointer", the direct `^string[N]` case shares `SymPtrElemStrCap` with the
pointer-to-array case. The two are disjoint — a pointer is to an array or to a
string, never both — and the shape of the assignment target tells them apart
(`p^` is the string, `p^[i]` an element of it), so one slot answers both.

The chain, all of it following `LastTypePointerStrElemTk`'s existing convention
rather than inventing one:

- `LastTypePointerStrCap` — captured in the ONE general `^T` arm, in the same
  one-statement window as the pointee kind.
- `AliasPtrStrCap` — an alias is where a pointer type is almost always spelled.
  Read from `LastTypeStrCap` and NOT from the pointer-side channel, because at
  alias registration both arms parse the POINTEE directly; the note above
  `AliasPtrStrElemTk`'s own assignment makes that argument at length and it
  applies unchanged.
- `SetPtrElemArrayInfo` — filled there, ABOVE the array early-exit, because it
  is the one procedure all four allocators call. Its siblings are zeroed at four
  separate sites, and an allocator that missed one would record 0, which the
  clamp helpers read as `DEFAULT_STR_CAP` — a silent overrun, not a diagnostic.
  (frankb-78 flagged that trap before I hit it.)
- `FrozenStrCapOfDeref` — the reader, beside `FrozenStrElemCapOf`. Deliberately
  not routed through `DerefPtrArraySym`, which requires `SymPtrElemArrLen > 0`
  and therefore answers −1 for exactly this case.

**A plain frozen `string` pointee records 0, not 255**, matching what `AllocVar`
does for `SymStrCap` — so this change does not add a second reading of 0, and
the writer-side correction above stays exactly as stated.

### Verification

- `p: ^string[8]`, `p^ := <16 chars>`: **len 8, neighbour intact**, on x86-64,
  i386, aarch64, arm32 and riscv32, in BOTH modes. Ten cells.
- **FPC 3.2.2 prints the test's seven lines byte-identically.**
- **Positive control:** the pre-fix compiler on the SAME test prints
  `ptrdirect 16 abcdefghijklmnop g=` — wrong length AND the guard clobbered
  empty — while the six pre-existing rows are unchanged. The row can fail, and
  it fails for the right reason.
- `test_shortstring_cap_through_a_pointer.pas` gains `ptrdirect` and is now
  wired for riscv32 as well as native/i386/aarch64/arm32.

### What is still open, and it is now its own ticket

The writer-side correction — `AllocVar` and `AllocParam` leaving a plain frozen
`string` at 0, so the eleven clamp sites cannot tell "255 is right" from "the N
was lost" — is filed as
[[bug-a-a-plain-frozen-string-records-capacity-zero-so-eleven-clamp-sites-cannot-say-unset]]
rather than left inside a closed ticket, so it stays in the ranker. It is
unblocked; it is a behaviour change across every consumer of `SymStrCap` and
wants its own control rather than riding along with a carrier fix.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c2ad9761e.
