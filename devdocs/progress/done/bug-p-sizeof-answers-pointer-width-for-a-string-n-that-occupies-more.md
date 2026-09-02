---
track: P
prio: 70
type: bug
blocked-by: []
found: 2026-09-02
found-by: frankB
resolved: 2026-09-02
owner: frankB
summary: "SizeOf reports POINTER WIDTH (8) for every `string[N]`, in all seven shapes, while pxx's own layout engine gives that same type cap+8 (18 for `string[10]`) -- so this is not an FPC divergence, it is SizeOf disagreeing with THIS compiler's storage. It reaches a value through the commonest idiom in Pascal: `FillChar(a, SizeOf(a), 0)` on an `array[0..2] of string[10]` clears 24 of the 54 live bytes and leaves a[2] intact, and `Move(a, b, SizeOf(a))` copies less than half, both silently and both correct under FPC. Every capacity table the fix needs ALREADY EXISTS and is already what the layout path reads -- AliasStrCap, SymStrCap, RecFieldStrCap, ArrTypeElemStrCap -- and FrozenStrSlotSize(tk, cap) is already the one answer used by record fields, array elements, symbol allocation and the ABI. Only SizeOf never asks. NOT the same thing as `string[N]` being cap+8 where FPC is cap+1: that is the representation question, and this bug is wrong under EITHER answer to it."
---

# SizeOf answers 8 for a `string[10]` that occupies 18 bytes

## The measurement

`type S10 = string[10]`, oracle `fpc -O- -Mobjfpc` 3.2.2, pxx at `ffe20a8bc`:

| shape | FPC | pxx |
| --- | ---: | ---: |
| `SizeOf(S10)` (type name) | 11 | 8 |
| `SizeOf(sv)` (var of the alias) | 11 | 8 |
| `SizeOf(inl)` (`var inl: string[10]`) | 11 | 8 |
| `SizeOf(A3)` (`array[0..2] of S10`, type) | 33 | 24 |
| `SizeOf(av)` (that array as a var) | 33 | 24 |
| `SizeOf(av[0])` (element) | 11 | 8 |
| `SizeOf(rv.f)` (record field) | 11 | 8 |

Uniform: **pointer width in every shape.** That uniformity is the finding. It is
not seven arms that each forgot a case -- it is one consistent answer that is
consistently wrong.

## Why it is a pxx bug and not a compat item

pxx's own layout does NOT use 8. Measured on the same binary:

    SizeOf(S10)                     8
    SizeOf(array[0..2] of S10)     24
    true element stride            18      <-- &av[1] - &av[0]

The array claims 24 bytes and its own elements are 18 apart. The layout engine
is right (`FrozenStrSlotSize` = cap+8 = 18) and `SizeOf` is wrong about it.

The record path proves the same split from the other side: `record f: S10; g:
Byte` measures 24 in pxx -- 18 for the field, +1, padded -- so `RecSize` uses
the true 18 while `SizeOf(rv.f)` on the very same field says 8.

## It reaches a value

```pascal
var a, b: array[0..2] of string[10];
a[0] := 'aaa'; a[1] := 'bbb'; a[2] := 'ccc';
FillChar(a, SizeOf(a), 0);          { clears 24 of 54 bytes }
Move(a, b, SizeOf(a));              { copies 24 of 54 bytes }
```

    fpc   after FillChar: [] [] []          after Move: [aaa] [bbb] [ccc]
    pxx   after FillChar: [] [] [ccc]       after Move: [aaa] [   ] []

`FillChar(x, SizeOf(x), 0)` is not an exotic construct; it is how Pascal clears
an aggregate. `GetMem(SizeOf(T))` has the same shape and allocates short.

This is the FOURTH instance of one class in this same function, and the
previous one is the same defect one spelling over. Its own comments
already record `type Currency = record ... end` measuring 8 instead of 12 and an
`array[0..2] of Integer` FIELD reporting the element size -- both "silent wrong
sizes, feeding GetMem and Move". See
[[bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts]] and
[[bug-p-sizeof-an-array-field-returns-the-element-size]].

The closest one is [[bug-p-sizeof-string-disagrees-with-the-storage-string-actually-gets]]:
"SizeOf(string) = 8, SizeOf(v) = 4 ... a wrong size handed to GetMem and Move,
silently". That fix unified the two tables answering what a BARE `string` is and
stopped at the bare spelling -- `string[N]` runs through the same arms and kept
the pointer width. **Fixed one arm of a double case; the sibling stayed broken**
(devdocs/dev/normalise-dont-special-case.md). Its test asserts SizeOf against
the measured stride, and the test here is deliberately that same shape.

## Where

`compiler/pasparser_expr.inc`, the SizeOf builtin. The two arms measured:

- the named-alias arm, `prevTok := TypeSlotSize(IntToTypeKind(AliasTk[aliasIdx]))`
  -- `AliasStrCap[aliasIdx]` sits unread beside it, and `symtab.inc` fills it
  *specifically* for this ("A frozen-string alias keeps its CAPACITY").
- the named-array arm, `prevTok := TypeSlotSize(szElemTk) * szFlatLen`
  -- `ArrTypeElemStrCap[szAi]` likewise.

`TypeSlotSize(tk)` takes only a kind, and a frozen string's size is not a
function of its kind -- that is the whole defect. `FrozenStrSlotSize(tk, cap)`
is the existing answer; every arm already holds the capacity it needs.

## The boundary -- do NOT "fix" plain `string`

`SizeOf(string)` = 8 in pxx against FPC's 256 and that row is HONEST: a plain
`string` in pxx is a managed handle, measured stride 8, `record a: string; b:
Byte` = 16. FPC's 256 is its default `string` being a `string[255]`. Two
representations, each reported faithfully -- the CLAUDE.md class, not a defect.

The defect is exactly the **nonzero frozen capacity** case.

## Not to be confused with the representation question

`string[10]` is cap+8 in pxx and cap+1 in FPC because pxx maps `string[N]` onto
`tyFixedString` (8-byte NativeInt length word) rather than `tyShortString`
(1 length byte), which is a DIFFERENT open question --
[[compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees]]
routes it to Track U. Worth recording for whoever takes that decision: **the
`tyShortString` kind already exists and `FrozenStrSlotSize` already returns
cap+1 for it**, which makes that decision cheaper than that ticket assumes.

This bug is wrong under either answer, and fixing it does not prejudge one.

## Gate

`make test` + self-host + cross. A size change is where the suite goes green
while the ABI moves underneath it. The positive control must be a **size** row:
a value-only test certifies the bug as correct, because every value that fits
is already right -- the `FillChar`/`Move` rows above are the ones that observe it.


---

## Resolved 2026-09-02 (frankB)

`SizeOfSlot(tk, cap)` in `symtab.inc`, beside `FrozenStrSlotSize`: a frozen
string with a recorded capacity sizes through `FrozenStrSlotSize`, everything
else through `TypeSlotSize` unchanged. `RecFieldByteSize` and the six SizeOf
arms in `pasparser_expr.inc` now pass the capacity each of them already held.

`cap <= 0` deliberately keeps `TypeSlotSize`: a zero means no capacity was
recorded, and the legacy overloaded `tyString`'s slot is described by
`TypeSlotSize` itself as "struct pointer / inline", so widening it would be a
guess. Every `string[N]` records its N.

Verified:

- `test/test_sizeof_stringn_matches_storage.pas`, wired beside its sibling.
  Twelve rows: seven size shapes asserted against the MEASURED STRIDE, the
  managed-`string` boundary row, `FillChar`, `Move`, and capacity truncation.
- **Positive control**: with only the routing disabled and the compiler rebuilt,
  the seven size rows go to 0 and the value rows to `fillchar 110` / `move 100`.
  Restoring gave a byte-identical binary (`7dc15fb61363`).
- The assertions are self-consistency, NOT FPC's constants, so they survive the
  open `tyFixedString` vs `tyShortString` question. Confirmed portable: all rows
  hold on i386, aarch64, arm32 and riscv32.
- `test_sizeof_array_field`'s `rec.S` row had frozen the number 8 and was right
  for the WRONG REASON -- a `string[7]` occupies 15 bytes here, fpc says 8 at
  7+1, and our pointer width was also 8. Rewritten as the field-sizes-like-a-var
  invariant that test's own header says it uses.
- `gate.sh quick` GREEN with the FPC seed canary PASS; self-host fixedpoint
  converged.

Still open, and untouched here: `string[N]` is cap+8 where fpc is cap+1. See
[[compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees]].
`tyShortString` already exists and `FrozenStrSlotSize` already returns cap+1
for it.

## Log

- Found and fixed in one pass while measuring the `string[N]` third of
  [[compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees]],
  commit be76fab5a. Filed already-resolved: it needed no coordination, ranking
  or memory, and exists so the three code comments citing this slug resolve.
