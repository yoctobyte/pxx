---
type: bug
track: A
prio: 8
summary: a fresh dyn-array call result used as a Copy() or `+` operand is never released — the whole array leaks, one per operand per evaluation, and the obvious park fix segfaults on non-managed element types
owner: frankB
---

## What

`Copy(MkArr(i))` and `MkArr(i) + MkArr(i)` leak the operand array. A named
variable in the same position is clean. Measured with `-dPXX_ALLOC_CENSUS`,
1000 trips, last threshold, at `4af4645ba`:

| expression | live |
| --- | --- |
| `b := MkArr(i) + MkArr(i)` (two call operands) | **5805** |
| `b := nv + MkArr(i)` / `b := MkArr(i) + nv` (one) | **2988** |
| `b := Copy(MkArr(i))` / `Copy(MkArr(i), 0, 1)` | **2988** |
| `ib := MkIA(i) + MkIA(i)` (`array of Integer`) | **2004** |
| `ib := Copy(MkIA(i))` (`array of Integer`) | **941** |
| `b := nv + nw` (named operands) | 10 |
| `ib := iv + iv` (named, integer) | 10 |
| `b := Copy(nv)` (named) | 10 |

One whole array per call operand per trip, and it leaks for `array of Integer`
too — so it is the **handle** that has no owner, not the elements.

This is the same ownership family as the eight pointer seams
(`b788c5865`, `65e15e5ab`): a lowering hands a fresh managed value to a consumer
that keeps a **raw pointer**. `AN_DYN_COPY` (ir.inc ~7395) and `AN_DYN_INSERT`
(~7757, and the splice-value arm ~7720) each spill a non-`AN_IDENT` source into
a `tyPointer` temp that retains nothing. The `AN_IDENT` arm beside them is
unaffected — it takes `LEA` of the symbol's slot, not the handle, which is
exactly why the named-variable rows above are clean.

## The obvious fix does not work — do not spend the afternoon I spent

Wrapping those three spills in `IRParkManagedDyn` (the helper written for the
pointer seams) **fixes the leak and segfaults**, and the split is by element
type:

| | `array of AnsiString` | `array of Integer` |
| --- | --- | --- |
| `Copy(call)` | 2988 → **15** | **SIGSEGV** |
| `call + call` | 5805 → **20** | **SIGSEGV** |
| named splice operand | clean 10 | **SIGSEGV** |

Bisected across my own three sites: the splice-value park alone breaks `iv + iv`
where `iv` is a **named** `array of Integer`, so it is not about freshness.

The control that matters: the **same helper on the same integer array is clean at
the pointer-cast seam** — `Pointer(MkIA(i))` reads 921/918/3, and
`Pointer(iv)` on a named integer array leaves the array intact (`len=4`,
`[0]=11`, `[3]=44` after 1000 parks). So `IRParkManagedDyn` is not broken, and
this is not a latent bug in the landed pointer-seam work. Something specific to
these two arms rejects a parked value.

Working hypothesis, **not confirmed** — the park round-trips the value through
`IR_STORE_SYM`/`IR_LOAD_SYM` on a dyn-array symbol, and these two arms want a
**data pointer** where the park hands back a **handle** (or vice versa). The
element type changes which of the two the surrounding code computes. `PXXMemCopy`
/ `PXXDynInsArrFill` then walk from the wrong base. Whoever takes this should
dump `PXXDBG='a.ir:*'` for `Copy(MkIA(i))` with and without the park and compare
the operand feeding `PXXClampLen`, rather than reasoning about it — that is the
step I stopped at.

## Why it is not simply "park only managed element types"

That would leave the integer rows (2004, 941) leaking and would grow a second
path for a concept that already has one, which is the thing
`normalise-dont-special-case` is about. The right fix decides ownership where
the copy CONSUMES the source, once, for every element type.

## Repro

`/tmp` scratch, but it is four lines:

```pascal
type TArr = array of AnsiString; TIA = array of Integer;
function MkArr(n: Integer): TArr; begin SetLength(MkArr,2); MkArr[0]:='a'+IntToStr(n); MkArr[1]:='b'; end;
for i := 1 to 1000 do begin b := Copy(MkArr(i)); Inc(sink, Length(b)); end;   { live=2988 }
for i := 1 to 1000 do begin b := Copy(nv);       Inc(sink, Length(b)); end;   { live=10   }
```

Found while sweeping managed seams after `4af4645ba`. Not fixed: the working
tree was reverted to HEAD and re-verified (`converged after 1 round(s)`, all
rows produce correct output with the leaks present).
