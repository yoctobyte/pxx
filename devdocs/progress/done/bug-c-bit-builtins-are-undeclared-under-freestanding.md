---
track: B
tags: [C, cfront, freestanding, gibux]
prio: 40
type: bug
blocked-by: []
summary: "__builtin_ctzll and the other bit builtins (clz, ctz, popcount, ffs, parity, bswap) failed under --freestanding with \"call to undeclared function: __pxx_builtin_ctz64\". cparser renames them to crtl helpers that are declared in stdlib.h and live in crtl, and a freestanding object has neither. A freestanding unit that mentions one now gets a static copy of exactly the helpers it uses. Gibux fs/event.c hit it."
status: done
owner: unassigned
---

# The bit builtins are undeclared under --freestanding

## Cause

cparser.inc renames `__builtin_ctzll` to `__pxx_builtin_ctz64` (and so on
for the family). The helpers are declared in crtl's stdlib.h and their
bodies are auto-pulled from crtl/src/stdlib.c. A `--freestanding` object
has no stdlib.h on its path and no crtl to link.

## Fix

CAddFreestandingBuiltins (cpreproc.inc) runs after preprocessing, under
`--freestanding` only. For each builtin the unit mentions, it adds:
- a static prototype, prefixed to line 1 so no diagnostic's line number
  moves;
- a static body, appended at the end. The bodies are the same as crtl's.

A unit that mentions none is untouched.

## Test

test/c_freestanding_bit_builtins.c (`--emit-obj --freestanding`) is driven
by a gcc-built main (`_main.c`) that compares 195 cases against gcc's own
builtins: "bits ok 195". The d9a0d9a599-era compiler refuses the file.
