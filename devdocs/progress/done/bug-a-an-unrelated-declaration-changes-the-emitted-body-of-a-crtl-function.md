---
slug: bug-a-an-unrelated-declaration-changes-the-emitted-body-of-a-crtl-function
track: A
prio: 85
type: bug
status: done
created: 2026-09-02
found-by: frankA
owner: frankA
blocked-by: []
summary: "RESOLVED, and it was a SILENT MISCOMPILE rather than the codegen-determinism question it was filed as. The 47-byte size divergence in crtl's qsort and bsearch was the symptom; the cause is that the C frontend resolved a called name by asking FindProc FIRST and only falling back to the symbol table, so a file-scope function shadowed a function-pointer PARAMETER of the same name -- and the function whose parameter got shadowed was crtl's own. Any TU defining a file-scope `cmp` re-aimed the `cmp(prv, cur)` inside qsort at the USER's function, in code the user never wrote, with no diagnostic. Measured against gcc: a decoy returning 0 left {5,3,9,1,7} unsorted (53917 vs 13579) and a descending decoy returned 97531 for an ASCENDING request; bsearch reported not-found for a key that is present. `cmp` is one of the most common names in C. Fixed by asking FindSym for a symbol at or above Procs[CurProc].ScopeBase -- this proc's own parameters and locals -- before FindProc, so nothing that resolves today changes unless a local genuinely shadows it. Guarded by test/c_crtl_callback_param_shadowed.c, which fails four of five rows on the pre-fix binary."
---

# An unrelated declaration changes the emitted body of a crtl function

## The measurement

Four C sources, one compiler (`90b2afd68ab7`), plain `--emit-obj` (so `-O0`),
reading the FUNC symbol sizes straight out of the object:

```
printf only                        qsort=669   bsearch=473
printf + a cmp fn, unused          qsort=622   bsearch=426
printf + cmp, address taken        qsort=622   bsearch=426
printf + qsort called              qsort=622   bsearch=426
```

Row 2 is the finding. The source is

```c
#include <stdio.h>
static int cmp(const void*a,const void*b){return *(const int*)a-*(const int*)b;}
int main(void){ printf("x\n"); return 0; }
```

`cmp` is never called, its address is never taken, `qsort` is never mentioned,
`<stdlib.h>` is not included. Defining it is enough to change `qsort`'s body by
47 bytes, and `bsearch`'s by the same 47. Those are exactly the two crtl
functions that call through a `int (*)(const void*, const void*)`.

This is the shape from
[[a-right-answer-from-a-stale-global-is-order-dependent]] — perturb an unrelated
declaration and watch the answer move — except here the answer is emitted code
rather than a value, and it moved.

## The bodies genuinely differ, structurally

Not a relocation or an alignment difference. `objdump -d` over the two `qsort`
bodies gives 141 instructions against 130, and the control flow differs:

```
< e9 9e 01 00 00 jmp 26e0f <qsort+0x286>
> e9 6f 01 00 00 jmp 26db1 <qsort+0x257>
```

Two objects built from unrelated sources, both containing a WEAK `qsort`, one of
which the linker discards.

## What was NOT demonstrated, said plainly

**No wrong answer.** Linking a TU that calls `qsort` against one that does not,
in BOTH orders so that each variant gets to be the weak winner, sorts correctly
either way:

```
q_user.o qsort size: 622      q_main.o qsort size: 669
order 'qu qm' -> 13579        order 'qm qu' -> 13579
```

So the two variants are behaviourally equivalent on this probe. This ticket
claims divergence, not incorrectness, and anyone picking it up should not
inherit the stronger claim.

## Why it is worth a ticket anyway

1. **It falsifies a premise the parked design rests on.**
   [[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]
   option (4) moves the runtime prefix into ONE COMDAT group, and its write-up
   argues that reordering the trailing tail would make the prefixes
   byte-identical across objects — "byte-identical prefixes is precisely the
   property COMDAT wants". Ten shifting bytes were the known obstacle; these are
   a second, larger, and different one, and no reorder addresses them.
2. **Weak linking is already choosing.** This is not a future problem introduced
   by COMDAT — since `243137302` exported crtl WEAK, every multi-object link has
   been discarding one of two non-identical bodies. Today that is invisible
   because they agree.
3. **The trigger is the wrong shape for a runtime.** Whatever the lowering is,
   crtl's code should not be a function of what the user's TU happens to
   declare. Finding the mechanism is likely to be cheap — the delta is 47 bytes
   in exactly the two functions that call through a comparator pointer, so the
   suspect is the indirect-call lowering choosing a different shape when no
   compatible function is in scope.

## First step for whoever takes it

`PXXDBG=a.ir:qsort` on rows 1 and 2 above and diff. The repro is four lines and
the signal is a symbol size, so the bisect is cheap; do not start from the
disassembly.

## Resolved 2026-09-02 — it was a miscompile, and the size divergence was only its shadow

The ticket said, twice and deliberately, that no wrong answer had been
demonstrated. That was accurate about what I had measured and wrong about the
world. The first step it recommended — `PXXDBG=a.ir:qsort` on rows 1 and 2, and
do not start from the disassembly — found the cause in one diff.

### What the IR said

Row 1 (no `cmp` anywhere in the TU), inside crtl's own `qsort`:

```
111: load_sym [sym=cmp]      <- the parameter
113: const_int 0
114: binop  (cmp, 0)         <- a null guard
115: jump_if_false
119: call_ind a=118          <- an INDIRECT call through the parameter
```

Row 2 (the TU also defines an unused file-scope `cmp`):

```
111: call a=816 b=108        <- a DIRECT call to a proc
```

The 47 bytes were the null guard and the indirect call collapsing into a direct
one. `qsort`'s call to its own fourth parameter had been re-aimed at the user's
function.

### The demonstration, against gcc

```
             pxx (pre-fix)   gcc
decoy returns 0 always   53917         13579     the array is never sorted
decoy sorts DESCENDING   97531         13579     an ASCENDING request, reversed
bsearch for a key present    -1             7     not found
```

The decoy is never passed to `qsort` and never called by the user. `asc` and
`desc` come out IDENTICALLY wrong while requesting opposite orders, which is the
tell that both ran a third function.

**`cmp` is one of the most common identifiers in C**, and the shadowed callee is
in crtl, so no user code shows the mistake.

### The cause and the fix

`cparser.inc`'s call path asked `FindProc(name)` first and reached the
symbol-table lookup — the indirect-call path — only when FindProc had MISSED.
`FindProc` knows nothing about scope, so a file-scope function always won.

The fix asks `FindSym` first, and accepts it only for a symbol at or above
`Procs[CurProc].ScopeBase` with a `SymProcSig` — this proc's own parameters and
locals, holding a function pointer. Nothing that resolves today changes meaning
unless a local genuinely shadows a global, which is exactly C's rule.

### What this says about the finding it came from

The size divergence was real and was a symptom. Recording it as "divergence, not
incorrectness" was the correct claim from the evidence I had, and it was the
thing that made the bug findable — a 47-byte delta in exactly the two functions
that call through a comparator pointer is a much sharper pointer than any wrong
answer would have been, because nothing was producing a wrong answer where
anyone was looking.

It also matters for
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]:
`qsort` and `bsearch` now have the SAME body in both TUs (669 and 473 in each),
so this particular obstacle to option (4)'s byte-identical prefixes is gone.
That does not restore the premise — it says one measured counterexample has been
removed, and the premise still needs establishing rather than assuming.

## Log
- 2026-09-02 — resolved, commit PENDING-COMMIT.
