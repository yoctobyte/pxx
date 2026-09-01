# A file-scope pointer-to-array SEGFAULTS on indexing; the identical local is correct

- **Type:** bug (Track C — C declaration parsing, `compiler/cparser.inc`)
- **prio:** 70
- **Status:** open

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
