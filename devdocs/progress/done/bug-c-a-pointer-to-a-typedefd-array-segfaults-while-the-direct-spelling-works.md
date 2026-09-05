---
track: C
prio: 45
type: bug
status: done
found: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "In C, `typedef double TA[4]; TA *p = &a; (*p)[i] = v;` was wrong while the identical program written `double (*p)[4] = &a;` was correct. FIXED in both declarator arms: the typedef's inherent dimension no longer folds onto the VARIABLE when the declarator has stars, and the length is recorded as the pointee's (SymPtrElemArrLen) — the same slot the parenthesised `elem (*name)[N]` arms already write. THE TWO ARMS FAILED DIFFERENTLY, which is why both had to land together: ablated at 10492cae86d8 the LOCAL spelling SEGFAULTS (rc=139) and the GLOBAL spelling prints `0.00 0.00` at rc=0 — silent, and the global arm is the one busybox-shaped code reaches. That also reconciles this ticket's two contradictory symptom reports: `segfault` and `0.00 0.00` are both real and are different ARMS, not a changed diagnosis. The carrier this ticket originally predicted (SymPtrElemArrLen staying 0) was NOT the discriminator — it is 0 in the working spelling too; `isArray` was."
---

# C: a pointer to a typedef'd array loses the pointee's shape

## Measured

Both programs, same compiler, `gcc` as the oracle:

```c
/* SEGFAULTS under pxx; gcc prints "1.50 6.00" */
typedef double TA[4];
int main(void) { TA a; TA *p = &a;
  for (int i = 0; i < 4; i++) (*p)[i] = (i+1)*1.5;
  printf("%.2f %.2f\n", a[0], a[3]); return 0; }
```

```c
/* correct under pxx: "1.50 6.00" */
int main(void) { double a[4]; double (*p)[4] = &a;
  for (int i = 0; i < 4; i++) (*p)[i] = (i+1)*1.5;
  printf("%.2f %.2f\n", a[0], a[3]); return 0; }
```

Both compile clean (`ok:` line, exit 0). Only the run differs.

Reproduced on `stable_linux_amd64/default/pinned` (pinned 2026-08-27), so this
predates the 2026-08-31/09-01 deref work and is not a regression from it.

## Where to look

`SymPtrElemArrLen` is the slot that says "this pointer's pointee is a fixed
array of N", and cparser writes it directly at `cparser.inc:5386` / `5486` /
`11128` -- registering no ArrType row, which is why the Pascal side's alias
route cannot answer for C pointers. The likely shape of the bug is that the
typedef'd declarator does not reach whichever of those sites the direct one
does, so `SymPtrElemArrLen` stays 0 and the deref keeps a scalar stride.

**Check the carrier before theorising about the stride**: `PXXDBG=a.symptr`
prints the pointer metadata a symbol was stamped with, and comparing the two
spellings' output is one command. A 0 there names the write site; a correct
value there means the reader is the bug and this is a different ticket.

## Why it is filed rather than fixed

Track C's lane, and the Pascal-side fix it was found from
([[bug-a-p-caret-index-is-only-correct-when-the-pointer-is-a-plain-identifier]])
cannot reach it: C has no named pointer alias, so `NodePtrAlias` answers -1 for
every C pointer by construction. This needs the C declarator path, not the
predicate.

## Re-measured 2026-09-05 (frankC), at 97788cf59 — the symptom and the cause are both different from the above

**It does not segfault.** Same source as the repro above, binary `dad98c7a5537`:

```
gcc   1.50 6.00
pxx   0.00 0.00   (rc=0, compiles clean)
```

A silent wrong value, not a crash. The write lands somewhere other than `a`,
and `a` is left untouched — with a global `double a[4] = {1,2,3,4}` the direct
spelling then reads back the ORIGINAL 1 2 3 4, which is how you can see the
store went elsewhere rather than being lost. This matters for ranking: prio 45
was set against "segfaults", and a silent wrong value in a shape real C uses is
the more dangerous of the two.

**The carrier this ticket names is not the discriminator.** `PXXDBG=a.symptr`
on both spellings, one line each (it fires once, from `Alloc*`, so it shows what
was recorded AT ALLOCATION and not any later stamping — worth knowing before
reading too much into the other fields):

```
TA *p              kind=17 isArray=TRUE  elemType=17 ... ptrElemArrLen=0
double (*p)[4]     kind=17 isArray=FALSE elemType=1  ... ptrElemArrLen=0
```

`ptrElemArrLen` is **0 in both**, including the spelling that WORKS. The
prediction above — "`SymPtrElemArrLen` stays 0 and the deref keeps a scalar
stride" — is therefore wrong as stated: 0 there is what the correct program
looks like too, at this point. The field that actually differs is `isArray`.

**The two spellings never meet.** `double (*p)[4]` has a PARENTHESISED
declarator, so `ParseCDeclType` consumes the whole thing including the name and
the declaration lands in the pointer-to-array arm at `cparser.inc:6258`
(`CTypeFnPtrName <> ''`), which sets `SymPtrElemArrLen` from `paLen`. `TA *p`
has no parens, so the name is left unconsumed and it falls through to the
ordinary name-reading loop — and there, `cparser.inc:6444`:

```pascal
if (CurTok.Kind = tkLBrack) or (tdArrLen >= 1) then
```

enters the FIXED-ARRAY path whenever the typedef carries an inherent dimension,
**with no test on pointer depth**. So `TA *p` is built as an array of four
pointers rather than a pointer to an array of four, which is exactly the
`isArray=TRUE` above.

## What the fix has to do

When the declarator has stars, a typedef's inherent dimension describes the
POINTEE, not the variable: suppress the fold at 6444 and record the length as
the pointer's element-row length instead, so the two spellings converge on the
same stamping.

Two cautions for whoever takes it:
- **Use the per-declarator star count, not the shared one.** `TA *a, b;` is a
  pointer and an array in one declaration; `declPtrDepth` (set in the
  multi-declarator arm around 6420) is the right variable, `ptrDepth` is not.
- **There are TWO arms.** `ParseCGlobalVarDecl` reads `CTypeTypedefArrLen` at
  `cparser.inc:9802` with the same shape. Fixing one and not the other is the
  sibling case `devdocs/dev/normalise-dont-special-case.md` is about, and the
  global arm is the one busybox-shaped code hits.

Parked rather than fixed: the declarator path has several interacting flags
(`declPtr`, `hadStar`, `declPtrDepth`) and two arms, and this is a fix to land
with its own gate rather than tacked onto another change.

## RESOLVED 2026-09-05 (frankC), and the two symptom reports were both right

Fixed in BOTH declarator arms, which is the part that mattered:

- `ParseCLocalDeclAST` — the fixed-array arm now requires `declPtrDepth = 0`
  before folding a typedef's inherent dimension onto the variable, and the
  plain-pointer registration writes `SymPtrElemArrLen` instead.
- `ParseCGlobalVarDecl` — the same guard, but it had no per-declarator depth to
  ask: its loop did `while CurTok.Kind = tkStar do Next;`, discarding the count.
  It now counts into `gStars` and consults `baseTk` only for the FIRST
  declarator, whose stars `ParseCDeclType` had already consumed. That answer is
  used ONLY for this guard, so `Sym *a, *b` binds exactly as before.

**Ablated at `10492cae86d8`:**

```
  local  `TA *p`  inside a function   SEGFAULT, rc=139
  global `TA *gp` at file scope       "0.00 0.00", rc=0, SILENT
  both direct spellings               correct, both compilers
```

**This reconciles the disagreement in this ticket's own history.** It was filed
saying SEGFAULTS; the 2026-09-05 re-measurement above says `0.00 0.00` and
"NOT a segfault, whatever this ticket originally said". Both are true and they
are **different arms** — the loud one and the silent one — so the re-measurement
was correcting a claim that had never been wrong, only unlabelled as to scope.
What I have NOT established is which arm the earlier `0.00 0.00` note was taken
from; it cites the local spelling, which segfaults today, so either the note or
the intervening commits moved it. Recorded rather than smoothed over.

**The predicted carrier was wrong and saying so saved the second attempt.**
This ticket originally expected `SymPtrElemArrLen` to be 0 for the broken
spelling. It is 0 for the WORKING spelling too, so it was never the
discriminator — `isArray` was. The parked diagnosis said this explicitly, which
is why the fix started at the fold site rather than at the slot.

**Both of the parked diagnosis's cautions were load-bearing**: the
per-declarator star count (`TA *a, b;` is a pointer and an array), and the
existence of the second arm.

Test: `test/c_pointer_to_typedefd_array.c`, all four spellings, matching gcc at
both widths (`-m32` identical). Rows 5-8 are the control on the GUARD — the fold
must still apply when there are no stars, and `TA gs[2]` -> [2][4] is what would
break first.

**Found while asserting that and NOT fixed here:** `sizeof` of the TYPE NAME
answers the element size (`sizeof(TA)` = 8 against gcc's 32). Ablated as
pre-existing. Filed as
[[bug-c-sizeof-of-an-array-typedef-name-answers-the-element-size]].

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 249e29cfa.
