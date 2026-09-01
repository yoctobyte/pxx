---
track: C
prio: 45
type: bug
status: open
found: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "In C, `typedef double TA[4]; TA *p = &a; (*p)[i] = v;` compiles clean and SEGFAULTS, while the identical program written `double (*p)[4] = &a;` is correct and matches gcc. Same declaration, two spellings, one of them loses the pointee's array shape. PRE-EXISTING, not a regression: reproduced on the Aug-27 pinned binary (stable_linux_amd64/default/pinned) as well as on tip. Found while fixing bug-a-p-caret-index-is-only-correct-when-the-pointer-is-a-plain-identifier, which is the same defect one frontend over -- there the carrier existed for a plain identifier and not for a field/call/element; here it is written for the direct declarator and not for the typedef'd one."
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
