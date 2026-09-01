---
slug: bug-c-a-field-past-the-first-eight-bytes-of-an-indirect-call-s-struct-result-reads-back-as-offset-zero
track: C
prio: 60
type: bug
blocked-by: []
status: backlog
found: 2026-09-02
found-by: frankC
owner: unassigned
summary: "x86-64, C frontend: a struct returned through a FUNCTION POINTER reads its third int back as its first when the field is used directly as a call argument. `struct P v = fp(3); printf(\"%d %d %d\", v.x, v.y, v.z)` prints `7 11 7` where gcc prints `7 11 13`. The struct in memory is CORRECT — copying the fields to locals first prints 7 11 13 — so this is the field READ in argument position, not the return. Needs an INDIRECT call: a plain local struct and a DIRECT call are both right. Silent wrong value, rc=0. Reproduces on the v399 pin, so it is not new."
---

# A field past the first eight bytes of an indirect call's struct result reads back as offset zero

Found while adding riscv32/xtensa coverage for
[[bug-a-riscv32-and-xtensa-still-refuse-aggregate-results-via-virtual-and-indirect-calls-under-a-done-ticket]],
by writing the C-frontend probe that ticket's marshalling change called for. The
probe disagreed with gcc on **x86-64**, which that change does not touch.

```c
int printf(const char *, ...);
struct P { int x, y, z; };
struct P mk(int s){ struct P p; p.x=7; p.y=11; p.z=13; return p; }
int main(void){ struct P (*fp)(int)=mk; struct P v=fp(3);
  printf("%d %d %d\n", v.x, v.y, v.z); return 0; }
```

```
gcc     7 11 13
pxx     7 11 7      <- v.z reads back as v.x
```

rc=0 either way. Nothing crashes, nothing warns.

## What it is NOT, each checked

| variation | result |
| --- | --- |
| plain local struct, no call at all | **correct** |
| struct from a DIRECT call | **correct** |
| four-field struct, plain local | **correct** |
| fields copied to `int` locals, then printed | **correct** |
| non-variadic callee instead of `printf` | correct *for a local struct* |
| 8 / 12 / 16 / 24-byte structs through a pointer, each printed in its own statement | **correct** |

So it is not the struct return, not the struct layout, not variadics, and not
the field offsets — `int a=v.x, b=v.y, c=v.z;` prints `7 11 13` from the very
same object. **The bytes are right; the read in argument position is wrong.**

The two conditions that must BOTH hold are: the struct came from an **indirect**
call, and the field is read **directly as a call argument**. Break either and it
is correct. That pairing is why the size sweep above came back clean — those
rows printed each struct in its own statement.

## The shape of the cause, not yet the cause

A destination temp is the obvious suspect: an indirect call's result needs a
caller-owned destination, and the failing read is the one that happens while a
NEW call's argument block is being built. `v.z` coming back as `v.x` is an
offset that lost its +8, or a base that was recomputed to the wrong object —
both are what a temp whose address is re-derived at the wrong moment looks like.

**Do not take that as the diagnosis.** It is the hypothesis to disprove first,
and `PXXDBG=a.ir:main` on the four-line repro is cheaper than reading the
emitter — that is what it is for.

## Bound

Reproduces identically on the **v399 pin** and at HEAD `174a53388c9b`, so it is
not a regression from anything landed today. Not measured on the other
backends: the probe reaches them only through the same source, and i386 and
riscv32 both MATCHED gcc on the larger version of it, which is worth knowing but
is not the same claim as a clean run of THIS repro.

## Why prio 60

A silent wrong value with rc=0 in a construct C code uses freely — a function
pointer returning a struct is ordinary in callback and vtable-shaped C, which is
exactly what the busybox and crtl work is compiling. Nothing in the tier chain
can see it: it does not crash, does not warn, and the field it corrupts is the
third one, so a two-field struct passes.
