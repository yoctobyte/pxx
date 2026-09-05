---
slug: bug-c-a-multi-dimensional-array-typedef-is-half-modelled-and-corrupts-neighbouring-locals
track: C
type: bug
prio: 85
status: done
found: 2026-09-05
found-by: frankC
blocked-by: []
summary: "FIXED 2026-09-05 (frankC), same day it was found. `typedef int T2[2][3];` recorded ONLY the first dimension -- CTypedefArrLen was one integer and the enclosing skip-to-semicolon loop ate the rest -- so an object of that type was allocated for 2 elements instead of 6 AND indexed with a 2-wide row. Measured with a T2 local bracketed by two ints: `before` read 1011 instead of 111 and v[0][1] returned v[1][0]'s value. Silent, rc=0. The shape is cglm's `mat4` = `typedef float mat4[4][4]`, and cglm is the library the recording site's own comment cites. That comment said a multi-dim typedef \"leaves it scalar (unchanged behavior)\" -- true of the code, false of the outcome, because the FIRST dim was still folded in, so it allocated a plausible 2 rather than a visibly wrong 1. Fix keeps ONE model: the direct spelling int v[2][3] already worked, so CTypedefNDims/CTypedefDims let the typedef carry what the declarator path already consumes. Verified at 4562c7728353: transcript identical to gcc natively and on i386/aarch64/arm32/riscv32, conformance 220/220, busybox 75 TUs GREEN on x86_64 and i386."
---

# A multi-dimensional array typedef is half-modelled, and the half is silent

Found while measuring
[[bug-c-sizeof-of-an-array-typedef-name-answers-the-element-size]] — the
`sizeof` defect is the visible edge of this, and this is much worse.

## Measured, compiler `f519214f643f`, gcc as oracle

```c
typedef int T2[2][3];
int main(void) {
  int before = 111;
  T2 v;
  int after = 222;
  for (i=0;i<2;i++) for (j=0;j<3;j++) v[i][j] = 1000 + i*10 + j;
  ...
}
```

```
pxx   sizeof(v)=8   before=1011  after=222
      v[0][0]=1000 v[0][1]=1010 v[0][2]=1011 v[1][0]=1010 ...
gcc   sizeof(v)=24  before=111   after=222
      v[0][0]=1000 v[0][1]=1001 v[0][2]=1002 v[1][0]=1010 ...
```

**Two defects in one, and both are silent.**

1. **Under-allocated.** 8 bytes where 24 are needed, so the writes run off the
   end and land on `before`, an unrelated local. `before` comes back 1011.
2. **Wrong row stride.** `v[0][1]` reads 1010 — the value written to `v[1][0]`.
   Rows are not 3 elements wide, so the two indices alias.

Neither produces a diagnostic and the program exits 0.

## Cause, and it is one line doing nothing

`cparser.inc`, the array-typedef recording site. Its own comment is accurate
about what it does and does not do:

```pascal
{ Only a single constant `[N]` is modelled; a multi-dim or unsized typedef
  array leaves it scalar (unchanged behavior). }
if (tk <> tyRecord) and (tk <> tyPointer) and (CurTok.Kind = tkLBrack) and
   (Tokens[TokPos].Kind <> tkRBrack) then
begin
  Next;
  ci := FindCTypedef(nm);
  if ci >= 0 then CTypedefArrLen[ci] := CEvalConstExpr;
  if CurTok.Kind = tkRBrack then Next;
end;
```

`CTypedefArrLen` is ONE integer (`defs.inc`: *"inherent length N (single
dim)"*). The `[3]` is then swallowed by the enclosing
`while (CurTok.Kind <> tkSemicolon) ... do Next`, which exists to skip the rest
of a declaration and cannot tell a dimension it should have modelled from
punctuation it should discard.

**"leaves it scalar (unchanged behavior)" was true of the code and false of the
outcome.** Leaving it scalar would answer 4 and allocate 4 — visibly wrong.
What actually happens is that the FIRST dimension is folded in and the rest are
dropped, which allocates a plausible-looking 2 elements and indexes as if the
type were `int[2]`. A half-applied model is worse than no model: it produces an
answer in the right neighbourhood, which is the one that survives review.

## Why the priority is not the sizeof ticket's

`sizeof` answering 8 is a wrong number. This is a wrong number, an
under-allocation and a stride error, in ordinary hand-written C. **cglm's
`mat4` is `typedef float mat4[4][4]`** — the exact shape — and cglm is the
library named in the recording site's own comment as the reason the single-dim
case was modelled at all. Anything doing 3D or linear algebra in C spells its
matrices this way.

## For whoever takes it

The direct spelling works: `int v[2][3]` allocates and indexes correctly, so
the multi-dim machinery exists (`MAX_ARR_DIMS`, the `dimSpan`/`beStack` paths
in `ParseCLocalDeclAST`). This is a typedef that cannot carry what the
declarator path already knows how to consume, not a missing capability —
`normalise-dont-special-case` rather than a second path.

**If the full model is too large for one sitting, REFUSE the declaration rather
than leaving it.** A `multi-dimensional array typedef is not modelled` error is
strictly better than silent neighbour corruption, and it is honest about the
gap in a way the current comment is not.

Check the sibling spellings before closing: an unsized `typedef int T[]`, a
typedef of an array of a record, and `typedef int T3[2][3][4]`.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
