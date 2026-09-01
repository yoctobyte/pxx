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

### Four hypotheses, all refuted — do not re-run these

I chased this after filing and eliminated every obvious cause. Recorded so the
next person starts where I stopped, not where I started.

1. **Handle vs data pointer** (my original guess, now DEAD). `PXXDBG='a.ir:*'`
   with the park applied, for `Copy(MkIA(1))` and `Copy(MkSA(1))`, emits
   **structurally identical IR** — same `store_sym`/`load_sym`/`store_sym` at
   nodes 3-5, same value reaching `PXXClampLen`. The element type changes
   nothing about the shape.
2. **`Copy` aliases the source buffer on a full-length copy.** No:
   `Copy(MkIA(i), 0, 2)` and `Copy(MkIA(i), 0, 4)` crash exactly like
   `Copy(MkIA(i))`.
3. **The scope-exit release is what crashes.** No: `WriteLn` after the loop never
   runs and the census dies at `allocs=8`, so the crash is INSIDE the loop —
   it is the per-iteration release of the slot's previous occupant.
4. **The parked temp is not nil-initialised.** No: the walker at
   `ir_codegen.inc:11571` nil-inits every `SymIsHiddenArgTemp` `skLocal`
   including dyn arrays, and a main-program temp is `skGlobal` in already-zeroed
   BSS. Both of my repro shapes are covered.
5. **Non-managed dyn arrays are not refcounted, so the park's release is an
   unbalanced extra free.** No: a local `array of Integer` assigned from a
   global, 50 trips, leaves the global intact (`11`/`44`), and FPC agrees. They
   are refcounted.

What survives: the crash is a per-iteration release, of an `array of Integer`
temp, at these two arms only, on a value the arm also consumes — and the same
release of the same array type through `IRParkManagedDyn` at the pointer-cast
seam is clean. The next step I would take is `-dPXX_HEAP_DEBUG` on the crashing
build plus `-dPXX_OBJTRACE` to get retain/release provenance for the one handle,
rather than another hypothesis.

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
