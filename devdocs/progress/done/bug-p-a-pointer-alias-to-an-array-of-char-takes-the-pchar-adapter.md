---
slug: bug-p-a-pointer-alias-to-an-array-of-char-takes-the-pchar-adapter
title: "`PCharA(@ca)^[1]` reads garbage: a pointer alias to an ARRAY OF CHAR is stamped with the PChar adapter, which overwrites the array row"
track: P
prio: 50
type: bug
status: done
found: 2026-09-04
found-by: frankA
owner: frankA
blocked-by: []
commit: PENDING-COMMIT
summary: "FIXED. The named-pointer-alias cast arm stamped the -2 PChar adapter whenever AliasElemTk = tyChar, which is a proxy for 'points at a character' and is equally true of `^array[0..3] of Char`. -2 goes in the SAME SLOT as aliasIdx, and aliasIdx is the only carrier of AliasPtrElemArrAi -- the pointee's array row -- so the subscript lost its element type and the AN_INDEX came out tk=0 (tyUnknown), a 4-byte read. `Ord(PCharA(@ca)^[1])` gave 1644192610 against fpc's 98; the char itself printed a 19-digit number that varied between runs. Silent, no diagnostic, present in pin v403. Fixed by asking AliasPtrElemArrAi < 0 alongside the tyChar test. Every NUMERIC element kind was always correct, so the flavour least likely to have a width bug was the only one that had one."
---

# What it was

`type TCharA = array[0..3] of Char; PCharA = ^TCharA;`

| spelling | pxx before | fpc 3.2.2 |
| --- | --- | --- |
| `c := PCharA(@ca)^[1]` | `b` | `b` |
| `Ord(PCharA(@ca)^[1])` | **1644192610** | 98 |
| `WriteLn(PCharA(@ca)^[1])` | **7061644217361130338** | `b` |
| `p := @ca; p^[1]` | `b` | `b` |

**The declared-target row was always right**, which is what kept this alive: an
assignment forces the width, so any test written the natural way passes. The
defect is in RVALUE position only.

# Mechanism

`pasparser_expr.inc`, the named-pointer-alias cast arm:

```pascal
if AliasElemTk[aliasIdx] = Ord(tyChar) then
  ASTIVal[node] := -2        { PChar adapter }
else
  ASTIVal[node] := aliasIdx;
```

The branch exists for `type PC = ^Char; PC(s)`, so that a custom alias to a bare
char behaves like `PChar(s)` and skips a managed string's 8-byte length prefix
(`bug-pointer-cast-custom-alias`). **`AliasElemTk = tyChar` is a PROXY for "the
pointee is a character", and it is equally true of a pointer to an ARRAY whose
elements are chars** — `LastTypePointerElemTk` records the element kind for both
shapes.

The damage is not the wrong adapter. **`-2` goes in the SAME SLOT as
`aliasIdx`**, and `aliasIdx` is the only thing carrying `AliasPtrElemArrAi`, the
pointee's ArrType row. With it overwritten, `DerefPtrElemArrAi`'s
`NodePtrAlias` route has nothing to answer from, the subscript never learns its
element type, and the `AN_INDEX` comes out **`tk=0`** — measured with
`PXXDBG=a.ast`, which showed `kind=39 ival=-2` over `kind=10 tk=0`.
`TypeSlotSize(tyUnknown)` is a 4-byte read, which is exactly the 1644192610.

The pointer-VARIABLE spelling was never affected: it asks the SYMBOL's
`SymPtrElemArrAi` and never passes through this stamp. **One construct, two
routes, and only the one that discards its row was wrong.**

# The fix

```pascal
if (AliasElemTk[aliasIdx] = Ord(tyChar)) and
   (AliasPtrElemArrAi[aliasIdx] < 0) then
```

Ask whether the pointee is a named array before treating it as a character.

# Why no numeric kind could ever have caught this

Measured before the fix: `PB(@b)^[1]`, `PW(@w)^[1]`, `PI(@i)^[1]`,
`PQ(@q)^[1]`, `PD(@d)^[1]` — byte, word, integer, int64, double — **all five
matched fpc exactly**, at five different element widths. None of them reaches a
branch keyed on `tyChar`.

So the obvious way to test "does indexing through a pointer-alias cast use the
right element size" is a numeric array, and it returns a clean pass at every
width. **The element kind least likely to be suspected of a width bug was the
only one that had one.** The test therefore carries the numeric rows as
CONTROLS, explicitly labelled as such, so nobody reads them as coverage.

# How it was found

Not by looking for it. I was validating a design for
[[bug-p-a-cast-to-an-array-type-is-not-recognised]] — the plan was to route
`TArr(aa)[1]` onto the pointer-alias path, since that ticket's own table records
`PArr(rawp)^[1]` as already working. **The check was "does the path I am about to
build on actually work", and for Integer it did.** Adding a char row to the same
probe is what broke it.

Two things worth keeping from that:

- **The ticket's table said the target path worked, and the table was right and
  insufficient** — it tested `PArr` (Integer). A design validated against it
  would have inherited this defect, and `bug-p-a-cast-to-an-array-type-is-not-recognised`'s
  own acceptance table demands `TCharA(ca)[1]` = `b`, so it would have failed at
  the last step for a reason nowhere near the change.
- **Validate the path you intend to build on, with the inputs your own gate will
  ask for**, before writing any of it.

# Gate

`make compiler/pascal26` (converged), `tools/gate.sh quick` GREEN read from the
log, FPC seed canary ran (dirty tree).

`test/test_ptr_alias_to_array_of_char.pas` + `.expected` (fpc 3.2.2's own
output, `diff` empty), wired. **Positive control:**
`stable_linux_amd64/default/pinned` differs on exactly the three rvalue rows
(`ord=6579042`, `inline=6579042`, `idx2=25699`) and agrees on `assigned=` and
`viaptr=` — which is the analysis above, confirmed by the pre-change binary
rather than asserted.

The `-2` adapter's own cases are in the same test and unregressed: `PCh(s)^`
over a managed string, and `PChar(s)[2]`, both identical to fpc.
