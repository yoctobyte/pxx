---
track: P
prio: 45
type: bug
status: working
blocked-by: []
owner: frankD
summary: "`GetPP^.a` where `GetPP: PPRec` and `PPRec = ^PRec = ^^TRec` is now REFUSED (`this value is still a POINTER here -- it needs another ^`) on a program fpc 3.2.2 compiles and runs, printing 11 and 22. That refusal arrived with frankB's f9476d579, which is right about the two-short chain and wrong about this one-short chain, and it fires HERE and nowhere else because this is the one opener where the depth is lost -- so the refusal and this bug are one defect seen from two sides. The field chain used to print 4306192 / 0 instead; the METHOD and PROPERTY chains (`GetPP^.GetA`, `GetPP^.PA`) still do. Controls, all measured at 85c81be85 / faa41e4b920f: `GetPP^^.a` written out in full is CORRECT; the pointer-VARIABLE twins `pp^.a` and `ppp^^.a` still print 11, so the refusal is opener-specific; and the two-short `GetPPP^.a` is refused by pxx AND by fpc (Illegal qualifier), which is frankB's arm doing its job. WHERE the depth is lost is NOT established: PXXDBG a.symptr shows the Result symbol carrying `depth=2 baseRec=23`, and seeding recId from ProcRetPtrBaseRec in the dot arm changed nothing -- but that probe cannot discriminate, because if the depth IS recorded then recId was already correct and the probe is a no-op. Pre-existing: the wrong VALUE is identical on pin v404; the refusal is not, it is new."
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

## 2026-09-06 — the observable changed under it: a FALSE REFUSAL, and it is the same defect

frankB landed `f9476d579` while this ticket sat open. It makes a pointer chain
that is one dereference SHORT **refuse** rather than answer a number, and frankB
asked to be told if a fix here made `GetPP^.a` resolve — with the warning to
check that `GetPPP^.a` still refuses rather than becoming a number.

**The measurement is the inverse of that expectation, and no fix was applied.**
Measured at `85c81be85`, binary `faa41e4b920f`, on a 41-row opener x chain
differential that moved from `agree=36 DIFFER=5 PXX-REFUSES=0` to
`agree=36 DIFFER=3 PXX-REFUSES=2`:

| program | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `GetPP^.a` (one short, call-result opener) | **refused** — `"a": this value is still a POINTER here` | compiles, prints `11 22` |
| `GetPPP^.a` (two short, call-result opener) | refused | refused — `Illegal qualifier` |
| `pp^.a` (one short, pointer VARIABLE) | 11 | 11 |
| `ppp^^.a` (one short, pointer VARIABLE at depth 3) | 11 | 11 |

So the new arm is **correct on the two-short chain** (row 2 is frankB's arm
doing exactly its job, confirmed against fpc) and **false on the one-short
chain**, and it is false *only* on the call-result opener. The pointer-variable
twins in rows 3-4 take the same one-short chain and still resolve.

**That opener is this ticket.** Where the depth is lost, a legal one-short chain
is indistinguishable from a two-short one, so a refusal aimed at the two-short
case necessarily swallows it. The two are not adjacent bugs to be sequenced —
they are one missing fact (`ProcRet*` depth at the call site) observed through
two different arms. **Fixing this ticket removes frankB's false positive as a
by-product; nothing needs to be reverted.**

The two remaining wrong-VALUE rows are `GetPP^.GetA` and `GetPP^.PA` — both
`4306192` against fpc's `11` — which are the same loss reaching the method and
property member kinds, where no refusal arm stands in front of them.

Whoever takes this inherits frankB's control as a required row: after the fix,
`GetPPP^.a` must still refuse. It does today, and it must not become a number.

