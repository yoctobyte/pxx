---
track: C
prio: 45
type: bug
status: open
found: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "In C, `typedef double TA[4]; TA *p = &a; (*p)[i] = v;` compiles clean and produces a SILENT WRONG VALUE, while the identical program written `double (*p)[4] = &a;` is correct and matches gcc. Re-measured at 97788cf59: it prints `0.00 0.00` where gcc prints `1.50 6.00`, rc=0 — NOT a segfault, whatever this ticket originally said. CAUSE MEASURED, and it is not the one this ticket predicted: `SymPtrElemArrLen` is 0 for BOTH spellings, so that carrier is not the discriminator. The two spellings take DIFFERENT BRANCHES — a parenthesised `(*p)[4]` declarator is consumed whole by ParseCDeclType and reaches the pointer-to-array arm, while `TA *p` falls through to the ordinary name loop, where `cparser.inc:6444` enters the fixed-array path on `tdArrLen >= 1` with NO pointer-depth guard. So the typedef's inherent [4] is folded onto the VARIABLE and `p` is stamped isArray=TRUE, instead of onto the pointee."
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
