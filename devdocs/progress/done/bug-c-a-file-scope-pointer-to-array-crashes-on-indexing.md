---
owner: frankC
---

# A file-scope pointer-to-array SEGFAULTS on indexing; the identical local is correct

- **Type:** bug (Track C — C declaration parsing, `compiler/cparser.inc`)
- **prio:** 70
- **Status:** done
## Measured
```c
#include <stdio.h>
int gm[3][4];  int (*gp)[4] = gm;
int main(void){
  int lm[3][4]; int (*lp)[4] = lm;
  int i,j;
  for (i=0;i<3;i++) for (j=0;j<4;j++) { gm[i][j]=i*10+j; lm[i][j]=i*10+j; }
  printf("local  lp[2][3] = %d\n", lp[2][3]);
  printf("global gp[2][3] = %d\n", gp[2][3]);
  return 0;
}
```

```
gcc   local 23   global 23
pxx   local 23   global SIGSEGV
```

The local is right. The global crashes. Same declarator, same initialiser
shape, one at file scope.

`sizeof` sees the same gap without crashing: `sizeof(*gp)` on a file-scope
`int (*gp)[4]` answers the wrong size where the local answers 16. That is the
symptom that led here — `bug-c-sizeof-of-a-pointer-to-array-struct-field-answers-the-pointer-size`
is the field spelling of the same family.

## What is NOT established
I first read `PXXDBG=a.symptr` as saying the global recorded no pointer
metadata. **That reading was wrong and the probe cannot answer this question:**
the dump is called from the `Alloc*` paths, i.e. at symbol ALLOCATION, while
the pointee shape is applied afterwards (`SymPtrElemArrLen[idx] := paLen`
follows `CAllocDeclVar`). So it prints zeros for the WORKING local too, and
"zeros" there means "not yet populated", not "never populated".

That is a second instance of the hole its own header warns about — the comment
says the probe was once blind to a whole Alloc path, and this is the same
animal one layer on: blind to later mutation. Worth fixing (dump after the
shape is applied, or dump both) so the next person is not misled the way I was.

So the only established facts are the runtime ones above. Whether the cause is
unrecorded metadata, a reader that does not look at file scope, or the
initialiser path is open, and whoever takes it should start from the crash and
not from my guess.

## Why it matters
A file-scope `elem (*p)[N]` is ordinary C — it is how you point at a row of a
2-D array without copying, and busybox/tcc-shaped code uses it. The failure is
a crash on the global and a silently wrong size on the same declaration, and
the local working is exactly what makes it hard to believe.

## Root cause — BOTH of the open guesses above, in the same branch

Measured 2026-09-02. `ParseCGlobalVarDecl` takes a private branch for a
parenthesised declarator (`cparser.inc`, the `CTypeFnPtrName` branch), and that
branch was written for function pointers. A pointer-to-array reaches it too,
and it was missing two different things there:

1. **No pointee metadata.** `ParseCLocalDeclAST` writes `SymPtrElemArrLen` /
   `SymPtrElemNDims` / `SymArrDimSpan` at two sites and `ParseCSubroutine` at
   one; the global branch had **zero** such writes. So `sizeof(*gp)` answered
   the element size (4) and the index stride was 4 rather than 16.
2. **No initialiser.** The branch's scalar `= expr` arm bound a FUNCTION name
   and nothing else, so `= gm` fell to its skip-to-semicolon and the pointer
   stayed **nil**. The braced arm beside it has classified a named global as
   `CGIArrKind = 2` all along — this is `normalise-dont-special-case`'s second
   path, the one that stays broken.

Either alone reproduces a wrong answer; together they gave the crash. The nil
is why it SEGFAULTed rather than merely reading the wrong element, which is
what the stride error alone would have done.

**A trap worth recording: recording order.** The metadata block must run AFTER
the branch's `if idx >= 0` block, because that block resets every scalar
pointer global to a `tyUnknown` pointee unconditionally. Recording before it
looked correct and moved `sizeof(*gp)` from 4 to **32** — 8 (the generic
pointer default) x 4 (the extent) — a plausible wrong number reached by a
correctly-computed extent multiplied into a defaulted element size.

**The ticket's warning about `PXXDBG=a.symptr` was right and is unchanged:**
the dump fires at `Alloc*` time, before any of this, so it cannot see the
recording site and prints zeros for the working local too. It did not answer
this and should not be trusted for it. Fixing the probe to dump after the
shape is applied is still worth doing and is not done here.

## Verified

`test/c_file_scope_pointer_to_array.c` (+ `.expected`). Every row is DERIVED,
never a spelled-out constant: the size is asserted against the measured stride
`(char*)(gp+1) - (char*)gp` and against `sizeof(gm[0])`, the real array being
pointed into, so a defaulted size cannot pass. The local `lp` rows are the
in-test control for the path that always worked.

Positive control, run against the **pinned** compiler (a genuine pre-fix
binary, no revert cycle): 5 rows FAIL and the binary then SEGFAULTs, while the
local rows pass. Post-fix, pxx and gcc both print `PTRARR OK stride=16`.

Row C/D (the struct-FIELD spelling) and row G (subscripting a pointer-to-
pointer) are unchanged by this and stay with their own tickets under
[[umbrella-sizeof-is-one-answer]].

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7d6559cd3.
