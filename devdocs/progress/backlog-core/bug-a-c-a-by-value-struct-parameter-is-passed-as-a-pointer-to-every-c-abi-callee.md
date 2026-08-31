---
track: A+C
prio: 60
type: bug
status: open
found: 2026-08-31
found-by: frankC
owner: frankC
summary: "A C function taking a struct BY VALUE is compiled to take a POINTER, on every target. Self-consistent inside pxx, so every existing test passes; a gcc caller passes the struct's bytes, our callee dereferences the first word as an address, SEGFAULT. Measured on x86-64 and i386 with gcc on the other side of the link, with a scalar-parameter control passing across the identical link. Root cause is one line: ABIParamSlotIsPointer in compiler/abi.inc returns True for tyRecord, so the whole C-ABI family -- direct, indirect, variadic, callee spill -- allocates one 8-byte pointer slot where the psABI wants the aggregate's own bytes classified into eightbytes."
---

# A by-value struct parameter is passed as a POINTER to every C-ABI callee

`ABIParamSlotIsPointer` (`compiler/abi.inc`) answers True for `tyRecord`, so a
by-value struct parameter occupies one pointer-sized slot everywhere in the
C ABI. Both sides of a pxx-only program agree, so nothing in the suite fails.
Across a real C boundary the callee dereferences the caller's *data*.

## Repro — three runs, and the third is the control

```c
/* pxx side */ struct Pair { int a; int b; };
               int take_pair(struct Pair p) { return p.a * 100 + p.b; }
/* gcc side */ struct Pair p = {3, 7}; printf("take %d\n", take_pair(p));
```

| both sides | result |
| --- | --- |
| gcc + gcc (`-m32` and native) | `take 307` — the oracle |
| pxx + pxx (i386) | `take 307` — self-consistent, which is why this was invisible |
| **gcc caller -> pxx callee** | **SEGFAULT**, x86-64 *and* i386 |

Control, same link shape, scalar parameters instead of a struct:
`take_ints(3,7)` -> `ints 307`. So the link, the object and the calling
sequence are all fine; the struct is the variable.

## Why no existing test sees it

`test-c-abi-cross`'s three subjects are all pxx-compiled on both sides —
deliberately, since they were built to catch a convention *change*, which is
self-consistent by construction either way. `test-c-abi-glibc-oracle` does
cross a real boundary, but only with scalars and a variadic tail through
glibc's `dprintf`; no glibc entry point in it takes a struct by value.
**The gap is the same one this ticket's family keeps rediscovering: a
self-consistent pair cannot judge a convention.**

## Scope — bigger than the one line

Changing the predicate is not the fix. The psABI wants the aggregate's own
bytes classified: SysV x86-64 splits into eightbytes with INTEGER/SSE classes
(and MEMORY past two), AAPCS64 has the HFA/HVA rule plus an 8-byte-slot copy
past the banks, AAPCS32 has its own. `ABIA64CdeclArgSlot` currently advances
NSAA by exactly 8 per stack argument, which is correct only while every slot is
a pointer. The callee spill (`EmitParamSpillsForTarget`) needs the mirror.

Returns are NOT in scope and appear to be right: `RetViaHiddenDest` implements
the hidden-destination convention and `cee_pairsum` matches gcc on four
targets.

## Found by

frankA asked whether the `ldr x9` single-word move in the aarch64 stack half
truncates a by-value aggregate spilled past the register bank, built the case,
and measured it MATCHING — because both sides were pxx. The negative result was
sound and the hypothesis was unreachable: the move is correct *by construction*
precisely because the slot is a pointer. Chasing why it could not fail is what
found this.

## Gate

A pxx object linked against a gcc caller, which nothing in the tree does for
structs yet. `test-c-abi-glibc-oracle`'s pattern extends to it: the new subject
must be `gcc main.c pxx.o`, not a pxx-only pair.
