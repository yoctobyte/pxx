---
summary: "On i386/arm32 a bare pointer-difference passed to a variadic function pushes 8 bytes instead of 4, so EVERY later argument reads the wrong slot — printf(\"%d %d\", p-q, 7) prints 3 0"
type: bug
track: A
prio: 65
---

# Pointer difference as a variadic argument pushes 8 bytes on 32-bit

- **Type:** bug — Track A (varargs lowering / expression width on 32-bit targets)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/gcc_diff_probe.sh --target i386` (first cross run of the
  new gcc-oracle differential). It surfaced as three unrelated-looking string.h
  divergences — `strchr`, `strstr`, `memchr` all "returning wrong pointers" —
  which were one bug in the caller's `printf`, not in crtl at all.

## Repro

```c
#include <stdio.h>
int main(void) {
  const char *s = "abcdef";
  const char *t = s + 3;
  printf("ptrdiff  : %d %d\n",   t - s, 7);
  printf("ptr-cast : %d %d\n",   (int)(t - s), 7);
  printf("three    : %d %d %d\n", t - s, 7, 8);
  return 0;
}
```

| | ptrdiff | ptr-cast | three |
| --- | --- | --- | --- |
| gcc | `3 7` | `3 7` | `3 7 8` |
| pxx x86-64 | `3 7` | `3 7` | `3 7 8` |
| pxx aarch64 | `3 7` | `3 7` | `3 7 8` |
| **pxx i386** | **`3 0`** | `3 7` | **`3 0 7`** |
| **pxx arm32** | **`3 0`** | `3 7` | **`3 0 7`** |

Every argument after the pointer difference is shifted by one 4-byte slot: the
callee reads the (zero) high half as the next argument, that argument as the one
after, and so on.

## Not UB — `%d` is the correct specifier here

`ptrdiff_t` is `int`-sized on ILP32, so `%d` with a pointer difference is
correct on i386/arm32, and gcc agrees. This is a genuine width bug, not a
format-specifier mistake.

The frontend already knows the right width — only the argument *push* is wrong:

```
i386:  sizeof(ptrdiff_t)=4  sizeof(void*)=4  sizeof(t - s)=4
```

`sizeof(t - s)` reports 4 while the varargs path pushes 8.

## What narrows it

- **Only the bare difference.** `(int)(t - s)` is correct — the explicit cast
  makes the pushed width right.
- **Only inline.** `ptrdiff_t d = t - s; printf("%d %d\n", (int)d, 7);` is
  correct. Assigning through a variable first was what made the original crtl
  probes pass and hid this for so long.
- **Only 32-bit targets.** On x86-64/aarch64 an 8-byte push is the correct
  thing, so the bug is invisible there — which is every developer's default
  build.
- **Harmless in the last argument position.** `printf("%d %d\n", 7, t - s)`
  prints `7 3`: nothing follows it to be displaced. So the failure depends on
  argument *order*, and a passing case proves nothing about a neighbouring one.
- Ordinary integer subtraction (`i - 1`) and char subtraction (`*t - *s`) are
  correct, so it is specific to the pointer-difference result type.

## Why it matters

`printf("%d bytes\n", p - buf)` is one of the most ordinary things C code does,
and on 32-bit it silently corrupts every argument after it. There is no
diagnostic anywhere; the first value even prints correctly, which is what makes
the following ones look like a *library* bug. That misdirection is the expensive
part: three crtl functions were the prime suspects for an hour.

Same family as [[bug-a-i386-int64-arg-high-half-uninitialized]] and
[[bug-c-int64-to-double-cast-truncates-on-32bit]] — 32-bit argument width.

## Gate

The repro above matches gcc on i386 and arm32;
`tools/gcc_diff_probe.sh --target i386` and `--target arm32` clean;
self-host fixedpoint; cross.
