---
track: C
prio: 15
type: compat
blocked-by: []
summary: "`printf(\"%p\", NULL)` prints `0x0`; glibc prints `(nil)`. Only the null case differs — a non-null pointer prints identically. It matters because it makes a gcc-oracle differential run report a divergence that is not a miscompile."
status: backlog
---

# `%p` of a null pointer prints `0x0`, glibc prints `(nil)`

- **Track C** (`lib/crtl`'s printf), tag **compat-c**.
- Found 2026-08-20 by a gcc differential probe over global initializers.

## What differs

```c
int *p = 0;
printf("%p\n", (void*)p);     /* glibc: (nil)    pxx: 0x0 */
```

Non-null pointers agree (`0x` + lowercase hex). C leaves `%p`'s representation
implementation-defined and musl prints `0x0` too, so neither is wrong — but the
gcc oracle we diff against IS glibc, so any C program that prints a null pointer
shows up as a divergence in a differential run and has to be eyeballed and
dismissed. That is the cost worth removing.

## Fix

One special case in `lib/crtl`'s `%p` conversion: a zero value formats as
`(nil)`. Guard it behind nothing — matching the oracle is the point.
