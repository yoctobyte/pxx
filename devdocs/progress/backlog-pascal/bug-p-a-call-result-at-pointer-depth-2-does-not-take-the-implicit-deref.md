---
track: P
prio: 45
type: bug
status: open
blocked-by: []
owner: 
summary: "`GetPP^.a` where `GetPP: PPRec` and `PPRec = ^PRec = ^^TRec` prints 4306192 and `.b` prints 0, where fpc 3.2.2 prints 11 and 22 — one dereference short, applied to the pointer VALUE. The last red cell of the implicit-deref census: every other opener (pointer variable at depths 1-3, pointer-alias cast at 1-3, call result at depth 1) now agrees with fpc for all three member kinds. `GetPP^^.a` written out in full is CORRECT, so the depth is recorded somewhere and is lost between there and ApplyCallResultPtrSuffix's dot arm. WHERE it is lost is NOT established: PXXDBG a.symptr shows the Result symbol carrying `depth=2 baseRec=23`, and seeding recId from ProcRetPtrBaseRec in the dot arm changed nothing — but that probe cannot discriminate, because if the depth IS recorded then recId was already correct and the probe is a no-op. Pre-existing: identical on pin v404."
---

# The last red cell of the opener × chain census

```pascal
type TRec = record a, b: Integer; end;
     PRec = ^TRec; PPRec = ^PRec;
var pp: PPRec;
function GetPP: PPRec; begin Result := pp; end;
...
WriteLn(GetPP^.a,  ' ', GetPP^.b);    { pxx 4306192 0   fpc 11 22 }
WriteLn(GetPP^^.a, ' ', GetPP^^.b);   { pxx 11 22       fpc 11 22 }
```

The explicit spelling is right, so this is not about the alias table and not
about the record identity — the address computation is one level short.

## What is measured, and what is not

`bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref` and
`bug-p-an-implicit-deref-over-a-typed-pointer-cast-is-dropped` are closed and
this is the cell they left. The 41-row differential (8 openers × field / second
field / method / property, plus two already-a-record negative-control openers,
plus a must-differ control) reads **agree=36 DIFFER=5**, and four of those five
are these rows; the fifth is the control.

**MEASURED:** `PXXDBG='a.symptr:*'` shows `GetPP`'s Result symbol as
`kind=17 depth=2 ptrElemTk=17 baseTk=5 baseRec=23 ptrElemAlias=14` — the full
triple, on the symbol.

**NOT ESTABLISHED:** whether `ProcRetPtrDepth[procIdx]` (a different array, and
the one `ApplyCallResultPtrSuffix` reads) carries it. Seeding `recId` from
`ProcRetPtrBaseRec` in that routine's `tkDot` arm changed no row —
**and that probe cannot tell the two cases apart**, because if the depth *is*
recorded then the caret arm has already set `recId := ptrBaseRec` and the
seeding is a no-op. A guard that cannot fail is not a guard, so the reading
that "the triple is empty" is withdrawn rather than reported.

## The next step, and why it needs a different instrument

A canary inside the arm is the obvious probe and it does not survive the
self-host: `compiler.pas` itself takes that arm, so the build fails before the
repro runs, and the compiler's own subset has no `IntToStr` to print the state
with. So the discriminator wants either a new `PXXDBG` topic for
`ProcRet*[procIdx]` at the call site — the sibling of `a.symptr`, which answers
about SYMBOLS and is exactly why the symbol reading above is not evidence about
the proc table — or a two-arm A/B where the seeding is applied unconditionally
rather than only when `recId = REC_NONE`.

Reached from `refactor-p-three-hand-rolled-postfix-loops`: the call-result walk
is one of the three, and this is the last shape where it still disagrees with
the shared walker it delegates to.
