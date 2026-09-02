---
slug: bug-a-an-unrelated-declaration-changes-the-emitted-body-of-a-crtl-function
track: A
prio: 45
type: bug
status: backlog
created: 2026-09-02
found-by: frankA
owner: ""
blocked-by: []
summary: "Defining an UNUSED static function whose signature matches a callback parameter shrinks crtl's own `qsort` by 47 bytes and `bsearch` by 47, measured at 90b2afd68ab7 -- 669 -> 622 and 473 -> 426. Not calling it, not taking its address: merely defining it. So a runtime function's emitted body depends on unrelated declarations in the user's translation unit, which means two --emit-obj objects carry DIFFERENT bodies for the same WEAK crtl symbol and the linker already picks arbitrarily between them today. NO DEFECT DEMONSTRATED: both variants sort correctly and both link orders give the right answer, so this is filed as a codegen-determinism and COMDAT-premise question, not as a wrong answer. It matters because feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl's option (4) assumes the runtime prefix is byte-identical across objects, and it measurably is not."
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
