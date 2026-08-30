---
track: C
prio: 22
type: compat
blocked-by: []
summary: "`printf(\"%p\", NULL)` prints `0x0`; glibc prints `(nil)`. Only the null case differs — a non-null pointer prints identically. It matters because it makes a gcc-oracle differential run report a divergence that is not a miscompile."
status: done
owner: frankC
---

# `%p` of a null pointer prints `0x0`, glibc prints `(nil)`

- **Track C** (`lib/crtl`'s printf), tag **compat-c**. RESOLVED 2026-08-29.
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

## RESOLVED 2026-08-29 (frankC, Track C)

`lib/crtl/src/stdio.c`'s `%p` arm now renders a null pointer as `(nil)`, and a
case is gated in `tools/gcc_diff_probe.sh` (`printf-p-null`).

### The one-line fix in this ticket would NOT have been enough

The ticket says *"a zero value formats as `(nil)`"*. Swapping the digits leaves
three of six spellings wrong, because glibc treats the null case as a plain
**string** while `%p` is otherwise on the numeric path. Measured against the
oracle rather than assumed:

| | glibc | a digit swap alone |
| --- | --- | --- |
| `%010p` | `␣␣␣␣␣(nil)` | `0x00000000` — `'0'` flag applied |
| `%.3p` | `(nil)` | `0x000` — precision padded |
| `%.0p` | `(nil)` | `0x` — C99's "precision 0, value 0 prints nothing" |

So the fix leaves the numeric path outright: it clears `prefix`/`preflen` (no
`0x`), clears `zero` (the `'0'` flag is ignored, field pads with spaces), and
clears `prec` (which is what stops the integer-precision block below from
claiming the conversion). Width and left-justify still apply, through the
ordinary string path — same shape as the existing `%s`-of-NULL → `(null)` case
directly beneath it.

Verified byte-identical to glibc across `%p %10p %-10p %010p %.3p %5p %.0p`.
Non-null `%p` is untouched and is asserted by **shape** rather than value
(`0x` + lowercase hex, length > 2), because a real address differs between the
gcc and pxx builds and cannot be diffed.

### The new probe case was checked for sensitivity, not just for green

Run against the pre-fix `stdio.c` it reports the divergence with both sides
printed, so it can actually fail:

```
DIFF  printf-p-null  gcc=[[(nil)]...]  pxx=[[0x0]<LF>[       0x0]...[0x00000000][0x000][0x]]
```

### Gate

- `tools/gcc_diff_probe.sh` — **119 cases, 0 NEW divergences, 0 known, 0 skipped**
- `crtl_libc_oracle`, `cprintf_hexfloat`, `cstring_batch` — each identical to gcc
- `make compiler/pascal26` — `converged after 2 round(s)`, fixedpoint verified
- Checked that nothing depended on the old spelling: no test or `.expected` file
  asserts `%p`-of-null as `0x0` (the `0x0` hits in `test/` are hex floats
  `0x0.0p+0`, preprocessor cases, and NilPy hex formatting — none reach this path)

Worth noting for the compat tag: this is **oracle agreement, not correctness**.
`%p`'s representation is implementation-defined and musl prints `0x0` too. The
value is that a C program printing a null pointer no longer shows up as a
divergence to be eyeballed and dismissed in a gcc differential run.

## Log
- 2026-08-29 — resolved, commit e885d94ef.
