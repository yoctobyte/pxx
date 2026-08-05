---
summary: "sscanf did not implement %[...] or %n — %[^,] abandoned the whole scan with the destination untouched, and %n left the caller's counter at whatever it held"
type: bug
track: B
prio: 45
---

# `sscanf` had no `%[...]` and no `%n`

- **Type:** bug — Track B (`lib/crtl/src/stdio.c`)
- **Status:** done
- **Opened / closed:** 2026-08-05
- **Found by:** `tools/gcc_diff_probe.sh`, second case batch
  ([[feature-c-gcc-oracle-differential-probe]]).

## Symptom

```c
char a[16] = "", b[16] = "";
int n = sscanf("abc123", "%[a-z]%[0-9]", a, b);   /* gcc: 2 [abc] [123] */
                                                  /* pxx: 0 []    []    */
int v = 0, consumed = -1;
n = sscanf("42abc", "%d%n", &v, &consumed);       /* gcc: 1 42 2 */
                                                  /* pxx: 1 42 -1 (untouched) */
```

Both fell into the `else break` "unsupported conversion" arm.

## Why each one is worse than a missing feature

- **`%[`** — `%[^,]` / `%[^\n]` is *the* way to read a delimited field in C, so
  hitting the unsupported arm abandons the whole scan mid-format: the return is
  short, and every destination from that point on is left untouched. A caller
  that checks the return survives; one that reads `a` after a partial match gets
  stale stack.
- **`%n`** — takes an argument but does **not** count toward the return value
  (C99 7.19.6.2p12). So the return looked completely correct while the caller's
  offset variable kept whatever it held, usually uninitialised. Nothing anywhere
  says so.

## Fix

Both implemented in `vsscanf`, with the edges the standard actually specifies:

- `]` first in a scanset is a literal `]`, not the terminator; `-` first or last
  is a literal `-`; `a-z` ranges (glibc-compatible, POSIX leaves it
  implementation-defined); an inverted range sets both endpoints and `-`.
- `%[` requires **at least one** matching character or it is a matching failure.
- Field width applies.
- `*` suppression consumes without assigning or counting.
- `%c`, `%[` and `%n` do **not** skip leading whitespace — the other conversions
  do. `%[` was the reason to touch that line: `sscanf("   xy", "%[^0-9]", a)`
  must capture the spaces.
- `%n` measures from the START of the input, not from where the current
  conversion began, and honours `l`/`ll`/`h`/`hh`.

## Regression cover

`sscanf-scanset-edges` and `sscanf-percent-n-positions` in
`tools/gcc_diff_probe.sh`, both byte-matched against gcc.

## Gate

`gcc_diff_probe` clean on native/i386/arm32/aarch64, `gate.sh lib` green,
c-testsuite 219/0/1.
