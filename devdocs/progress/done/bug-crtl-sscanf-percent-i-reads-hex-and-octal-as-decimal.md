---
slug: bug-crtl-sscanf-percent-i-reads-hex-and-octal-as-decimal
track: crtl
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Path B's xkbcomp turned Private(type=0x86) into NoAction)
tags: [crtl, stdio, scanf]
summary: "crtl's vsscanf read `%i` as base 10, so `0x86` scanned as 0 and `017` as 17. C says `%i` takes the base from the prefix, as strtol(..., 0) does. xkbcomp reads action fields with `sscanf(buf, \"%i\")`, and every Private action in the keymap came out as NoAction. The integer path now passes base 0 for `%i`. Test c_xgaps26 against gcc."
---

# sscanf %i reads hex and octal as decimal

```c
int base = (conv == 'x') ? 16 : (conv == 'o') ? 8 : (conv == 'i') ? 0 : 10;
```

`%i` fell into the decimal default. Checked against glibc for decimal,
hex (both cases of the `0x` prefix), octal, signs and trailing junk.

One known difference remains: a lone `"0x"` with no hex digit. glibc
consumes it and returns 0 conversions; crtl reads the `0` and stops at
`x`. Nothing in Path B depends on it, and the test leaves it out.
