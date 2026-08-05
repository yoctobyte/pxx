---
summary: "_Bool is plain tyUInt8, so conversion to it truncates instead of normalising: `_Bool b = 256` is FALSE, `_Bool b = ptr` is the pointer's low byte, and `b == 1` is false after `b = 5`"
type: bug
track: A
prio: 60
---

# Conversion to `_Bool` truncates instead of normalising to 0/1

- **Type:** bug — Track A (shared type system; the fix needs `_Bool` to be
  distinguishable from `unsigned char`, which is a `defs.inc`/symtab change)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/gcc_diff_probe.sh`, third case batch
  ([[feature-c-gcc-oracle-differential-probe]]).

## Repro

```c
#include <stdio.h>
int main(void) {
  _Bool t = 5, z = 0, c = (_Bool)2;
  int p = 42;
  _Bool fromptr = (_Bool)(void*)&p;
  printf("assign5=%d cast2=%d zero=%d ptr=%d\n", (int)t, (int)c, (int)z, (int)fromptr);
  printf("eq1=%d eq5=%d\n", t == 1, t == 5);
  { _Bool a[3]; a[0] = 7; a[1] = 0; a[2] = 256;
    printf("arr=%d %d %d\n", (int)a[0], (int)a[1], (int)a[2]); }
  { int n = 300; _Bool b2 = n; printf("from256=%d\n", (int)b2); }
  return 0;
}
```

| | gcc | pxx |
| --- | --- | --- |
| `assign5 cast2 zero ptr` | `1 1 0 1` | `5 2 0 116` |
| `eq1 eq5` | `1 0` | `0 1` |
| `arr` (7, 0, 256) | `1 0 1` | `7 0 0` |
| `from256` (300) | `1` | `44` |

`sizeof(_Bool)` is 1 on both, so the storage is right; only the conversion is
missing.

## Why it is worse than it first looks

C99 6.3.1.2 is unusually explicit: *"When any scalar value is converted to
`_Bool`, the result is 0 if the value compares equal to 0; otherwise, the result
is 1."* Without that:

1. **A true value becomes false.** `_Bool b = 256;` truncates to 0. `_Bool b = n;`
   with `n = 300` gives 44 — true, but the 256 case is a plain `if (b)` reading
   FALSE for a nonzero input. There is no diagnostic.
2. **A valid pointer becomes false.** `_Bool ok = ptr;` keeps the pointer's low
   byte; one in 256 valid pointers is a multiple of 256 and reads as NULL. This
   is the ugliest form — it depends on the allocator and will not reproduce.
3. **`b == 1` fails after `b = 5`.** Comparing a bool against `1` or `true` is
   ordinary code, and it silently stops matching.

## Cause

`_Bool` is lexed to `tkCBool` (`clexer.inc:30`) and mapped straight to
`tyUInt8` (`cparser.inc:3706`), with `cparser.inc:3786` commenting it as "a
1-byte integer type". After `CParseTypeSpec` returns, **nothing distinguishes
`_Bool` from `unsigned char`**, so every assignment and cast to it is a plain
truncating store.

Note `lib/crtl/include/stdbool.h` does `#define bool int`, so `<stdbool.h>`
code is unaffected — this only bites source that spells `_Bool` directly, which
is why it has gone unnoticed.

## Why this is Track A and not Track C

The C frontend cannot fix it alone: it needs `_Bool` to remain distinguishable
from `unsigned char` at the point of *use*, not just at the declaration, so the
assignment/cast paths can insert a `!= 0`. That means either a new type kind or
a per-symbol/per-type flag in the shared `defs.inc`/`symtab.inc` — shared
internals, Track A's ground. (The out-of-band pattern already exists nearby:
`CTypeIsVoid` / `CTypeLong` / `CTypeLongLong`, but those describe the
declaration being parsed, not the type carried onward.)

Suggested shape: a distinct `tyBool8` that lowers to the same 1-byte storage,
with the conversion-to-bool normalisation applied at assignment, cast, argument
passing and return.

## Gate

The repro matches gcc on every target; `tools/gcc_diff_probe.sh` case
`bool-and-negative-zero-int` clean (currently tagged `known`); self-host
fixedpoint; cross.
