---
track: C
prio: 25
type: bug
blocked-by: []
summary: "`__crtl_utoa`'s digit loop has no bound on its index, so a wrong `base` turns a printf into an unbounded stack write that smashes the routine's own parameters and then walks to the guard page. Do NOT fix in isolation — it is the amplifier for an unnamed defect and bounding it would hide that."
---

# `__crtl_utoa`'s digit loop is unbounded

`lib/crtl/src/stdio.c:102`:

```c
static int __crtl_utoa(char *out, unsigned long long v, int base, int upper) {
  char tmp[32];
  int n = 0, i, r;
  ...
    while (v) {
      r = (int)(v % (unsigned long)base);
      ...
      tmp[n++] = d;            /* <- n is never checked against 32 */
      v = v / (unsigned long)base;
    }
```

For every base printf actually passes (8, 10, 16) a 64-bit value needs at most
22 digits, so `tmp[32]` is correctly sized **as long as the loop terminates**.
It has no defence for when it does not.

## Why that is worse than an ordinary overflow

Measured in the emitted frame (2026-08-15, while working
[[bug-b-reportlab-mimic-multi-font-heap-corruption]]):

| frame slot | offset | tmp index that reaches it |
| --- | --- | --- |
| `tmp[32]` | `rbp-60` | — |
| `upper` | `rbp-24` | 36 |
| `base` | `rbp-20` | 40 |
| `v` | `rbp-16` | 44 |
| `out` | `rbp-8` | 52 |

The buffer overflows into **its own parameters**, and `base` is one of them. So
a loop that fails to terminate for any reason corrupts the very variable that
decides termination, and the write then runs unbounded up the stack to the guard
page. A cosmetic wrong-number bug becomes a stack smash with a `?? ()`
backtrace, three frames from anything meaningful.

Observed exactly that: 16 correct hex digits, then `f` repeated as `v` stuck at
all-ones, then `F` and `|` as the garbage `base` took over, then `n = 9533` and
`SIGSEGV` on the guard page.

## Do NOT fix this on its own — read this first

Bounding the loop (`if (n >= (int)sizeof(tmp)) break;`) makes the symptom
vanish, and the defect that stopped `v` shrinking would still be there,
producing a silently truncated number instead of a crash. That trade is worse:
the crash is the only reason anyone found it.

So: fix it **with or after** the root cause in the reportlab ticket, and keep a
repro of the non-terminating case first. If the root cause turns out to be
elsewhere entirely and this is genuinely just hardening, the bound is still
worth having — but land it knowing which of the two it is.

## Gate

`printf`-family output unchanged for the ordinary bases and widths
(`test/ccrtl_*` printf coverage), plus whatever repro the root cause produces.
