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

## Fixed 2026-11-19 (pxx2)

There were three faults, and the ticket's two lines hit different ones:

1. **`typedef struct D **PPD` was registered as `struct D *`.** The two
   struct-typedef arms of ParseCTypedef (with a body, and tag-only) counted the
   stars and ignored the count, so `q[0]` was the struct itself. Two or more
   stars now go through CAddStructPtrPtrTypedef.
2. **No typedef recorded its pointer depth.** New CTypedefPtrDepth and
   CTypedefPtrBaseTk fields. ParseCDeclType gives a `T **` typedef its depth
   and base whether it is used bare (`PPD q` is `struct D **q`) or under more
   stars (`PPD *x` is three levels). CTypeTdLvl tells the multi-declarator code
   that this depth is not a star the first declarator wrote, so
   `PPD a, *b, c;` gives each sibling the right level.
3. **`((struct D **)p)[0]->w`, and every index-then-arrow three levels deep
   (`z[0][0]->w` and `(*z)[0]->w` over `struct D ***z`), with no typedef
   involved.** ResolveNodeRec's deref-of-index arm handled only an identifier
   or a field under the index. It now handles a cast, and counts deeper
   index/deref chains against the declared depth, the same rule as the
   implicit-deref arm.

Test: test/c_ptr_ptr_typedef.c, rows c_ppstruct26 and c_ppstruct26_i386,
matching gcc. It covers variables, aliases, siblings, three levels, casts,
parameters, members, sizeof and stride. A differential sweep of all 48
standalone test/c_*{typedef,ptr,struct}*.c files against gcc is all SAME.
