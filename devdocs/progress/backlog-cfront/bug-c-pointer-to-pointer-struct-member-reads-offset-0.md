---
slug: bug-c-pointer-to-pointer-struct-member-reads-offset-0
track: C
prio: 60
type: bug
status: backlog
created: 2026-11-17
found-by: pxx2 session, Path B (X11 stack through pxx), while fixing bug-c-cast-through-a-pointer-typedef-loses-the-pointee
tags: [cfront, wrong-code, regression]
blocked-by: []
summary: "`((struct D **)pp)[0]->w` reads the FIRST field (offset 0) instead of w, and a `typedef struct D **PPD; PPD q; q[0]->w` / `(*q)->v` reads garbage. The September pin (v452) gets the cast form right, so that half is a regression since the pin. Silent wrong values, no diagnostic."
---

# C: struct member through a pointer-to-pointer reads offset 0

Repro (gcc prints `2 40` twice):

```c
#include <stdio.h>
struct D { int v; int w; };
typedef struct D **PPD;
int main(void){
  struct D d = {40, 2}; struct D *pd = &d; void *pp = &pd;
  PPD q = (PPD)pp;
  printf("%d %d\n", q[0]->w, (*q)->v);                                  /* pxx: garbage */
  printf("%d %d\n", ((struct D **)pp)[0]->w, (*(struct D **)pp)->v);    /* pxx: 40 40 */
  return 0;
}
```

Measured 2026-11-17 at 807b245698 (before and after the one-level pointer
typedef cast fix, same output):
- line 1: two garbage values with pxx (both the index and the deref form);
- line 2: `40 40`; `stable_linux_amd64/default/pinned` (v452) prints `2 40`.

Related: bug-c-a-pointer-typedef-loses-its-base-under-indexing (a pointer
typedef as the base of a further pointer). The cast fix in cparser.inc
deliberately stops at one level (`castElemTk <> tyPointer`) because a `T **`
typedef records no depth; this ticket is where the depth has to come from.
