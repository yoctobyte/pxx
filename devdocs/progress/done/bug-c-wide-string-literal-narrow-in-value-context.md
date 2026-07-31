---
summary: "L\"...\" stays narrow bytes outside an array initializer, so wchar_t* reads 4 chars per element and walks off the end"
type: bug
track: C
prio: 70
---

# `L"..."` is not widened in value/pointer context

- **Type:** bug — **silent wrong values** (Track C, C frontend)
- **Filed:** 2026-07-31 by Track T (xeon) from an `optdiff` NEW-RED.
- **Found at:** `f9396231e` (xeon, gcc 15.2 / kernel 7.0). Reported by the
  watcher at `2add2ebb487b`.

## The defect

A wide string literal is widened to `wchar_t` **only on the array-initializer
path**. Used as a value — assigned to a `wchar_t*`, passed as an argument, or
measured with `sizeof` — it stays as **narrow UTF-8 bytes**.

`compiler/clexer.inc:466` lexes it and marks the token wide
(`CurTok.IVal := 1`), and its own comment scopes the intent precisely:

> `CurTok.IVal := 1` marks it wide **so the array-init path** decodes
> UTF-8 -> wchar_t codepoints (00220)

Nothing does that decode for the value form, so the bytes reach codegen unwidened.

## Isolated repro — the two forms, side by side

```c
#include <stdio.h>
#include <wchar.h>
int main(void) {
  wchar_t arr[] = L"abcde";        /* array-init path  */
  const wchar_t *ptr = L"abcde";   /* value/pointer path */
  printf("arr: len=%d sizeof=%d c0=%d c1=%d\n",
         (int)wcslen(arr), (int)sizeof(arr), (int)arr[0], (int)arr[1]);
  printf("ptr: len=%d c0=%d c1=%d\n", (int)wcslen(ptr), (int)ptr[0], (int)ptr[1]);
}
```

| | gcc (oracle) | pxx |
|---|---|---|
| `arr` | len=5 sizeof=24 c0=97 c1=98 | **len=5 sizeof=24 c0=97 c1=98** — correct |
| `ptr` | len=5 c0=97 c1=98 | **c0=1684234849 c1=101** — wrong |

`1684234849` = `0x64636261` = the bytes `a b c d` packed into one 4-byte
`wchar_t`. `c1 = 101` is `'e'`. The literal is plainly still narrow.

And directly:

```
sizeof(L"abcde")   gcc: 24     pxx: 6        (sizeof(wchar_t) = 4 on both)
```

6 is the *byte* length. `sizeof` is a compile-time constant, so this is decided
in the frontend — not codegen, not `lib/crtl`.

## Consequence

`wcslen(L"...")` runs off the end of the literal and counts whatever follows in
memory. It is not a stable off-by-one — it returns whatever adjacent data
happens to say:

```
test/crtl_libc_oracle.c, line 13:   -O0 wcslen=4    -O2 wcslen=5    -O3 wcslen=4
                                    gcc oracle: 5
```

Every wide string literal in value position is affected, and every `wcs*` call
on one reads out of bounds.

## NOT an -O3 codegen bug — please don't hunt there

The watcher surfaced this as `optdiff#shard5/6` RED, tier `opt`, reported as an
**"OPT DIFF -O3"** with a segfault. That framing is misleading and cost this
investigation a detour, so it is written down here:

The `-O`-level disagreement is a **symptom**. Reading past the end of a
too-short literal picks up different adjacent bytes depending on layout, and
layout moves with optimisation — so `-O0`/`-O2`/`-O3` disagree with each other
*and* with gcc, non-uniformly. At `f9396231e` it is `-O2` that happens to agree
with the oracle and `-O0`/`-O3` that are wrong, which is the reverse of what the
report suggests. Nothing here indicts the `-O3` passes.

This is the class CLAUDE.md warns about: the bug produces a plausible wrong
value far from the cause. `optdiff` earned its keep by detecting it; it just
cannot name it.

## Fix

Widen `L"..."` wherever it becomes a value, not only in an array initializer:
emit a static `wchar_t` array (UTF-8 decoded to codepoints, 4-byte elements,
wide NUL terminated) and use its address. `sizeof` on the literal must then be
`(n+1) * sizeof(wchar_t)`. The array-init path at `00220` already does the
decode and can be reused rather than reimplemented.

Worth checking in the same pass: `L'x'` wide character constants, and wide
literals as function arguments and in `struct` initializers.

## Verify with

```sh
tools/testmgr.py --tier opt --job 'optdiff#shard5/6'
# and directly, since optdiff only reports THAT levels differ:
gcc -w -o /tmp/o test/crtl_libc_oracle.c -lm && /tmp/o | sed -n 13p   # wcslen=5
```

Track T filed this and does not fix it (T owns the tool, never the bug).

## Log
- 2026-08-01 — resolved, commit 6491f0c30.
