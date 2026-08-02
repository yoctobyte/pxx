---
track: C
prio: 80
type: bug
---

# Plain `char` is unsigned at runtime but signed when constant-folded

- **Type:** bug (C frontend, silent wrong value) — **Track C**
- **Found:** 2026-08-02 by the Track B agent, probing integer semantics against
  gcc for [[feature-crtl-implement-libc-assumptions]].

## Two defects, and the second is the nastier one

### 1. Plain `char` is UNSIGNED where the ABI says signed

On x86-64 and i386 the psABI makes plain `char` **signed**, and gcc follows it.
pxx treats it as unsigned:

| expression (`char c = (char)0xFF;`) | gcc | pxx |
| --- | --- | --- |
| `(int)c` | **-1** | 255 |
| `c < 0` | **1** | 0 |
| `c + 0` | **-1** | 255 |
| global / array element / `*p` | **-1** | 255 |
| `(int)(signed char)0xFF` | -1 | -1 (correct) |

Runtime behaviour is at least *self-consistent*: every plain-`char` form reads
as unsigned, and explicit `signed char` works.

### 2. Constant folding disagrees with runtime — same expression, two answers

```c
char rt = (char)-1;
(char)-1 < 0   /* folded  */  gcc 1   pxx 1
rt < 0         /* runtime */  gcc 1   pxx 0
(int)(char)-1  /* folded  */  gcc -1  pxx -1
(int)rt        /* runtime */  gcc -1  pxx 255
```

So the folder treats `char` as signed while codegen treats it as unsigned. That
is worse than either choice consistently applied: an expression's meaning
depends on whether a value happened to be known at compile time, so moving a
constant into a variable — refactoring, or just a debug print — changes the
answer.

## Why it matters

`char` arithmetic going through a sign is ordinary C, not a corner:

- UTF-8 handling is built on `if (*p < 0)` / `(*p & 0xC0) == 0x80` to spot
  continuation bytes;
- `getchar()`-style loops compare a byte against a negative `EOF`;
- hand-rolled comparators and hash loops do arithmetic on `char`;
- `char`-based flags with the high bit set.

None of it errors. It computes a plausible wrong number, which is this repo's
stated worst class.

## Per-target, since the right answer is not the same everywhere

pxx today, `(char)-1 < 0` folded vs `(int)c` at runtime:

| target | ABI requires | pxx folded | pxx runtime |
| --- | --- | --- | --- |
| x86-64 | signed | signed | **unsigned** |
| i386 | signed | signed | **unsigned** |
| aarch64 | **unsigned** | unsigned | unsigned ✓ |
| arm32 | **unsigned** | **signed** | unsigned |

aarch64 is the only target that is both correct and self-consistent, and only by
coincidence — its ABI happens to match what codegen already does. arm32 has the
fold/runtime split with the signedness flag set the wrong way for its ABI too.

## Fix shape

Make plain `char`'s signedness a **per-target property** — signed on
x86-64/i386, unsigned on aarch64/arm32 (and riscv, which is unsigned) — and use
that one property in *both* the constant folder and codegen, so the two cannot
drift. The bug is really that two places each decided independently.

A `-fsigned-char` / `-funsigned-char` override is worth adding at the same time:
real projects pass it, and once the property is single-sourced it costs almost
nothing.

## Gate

Every row of both tables above matches gcc for the target, and the folded and
runtime forms of the same expression agree with each other on every target. Plus
a UTF-8 continuation-byte probe (`*p < 0` over a multi-byte string) giving the
same answer as gcc.
