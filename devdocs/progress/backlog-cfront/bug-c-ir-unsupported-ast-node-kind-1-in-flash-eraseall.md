---
slug: bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall
title: "C frontend cannot lower AST node kind 1 in miscutils/flash_eraseall.c"
track: C
prio: 55
type: bug
status: open
created: 2026-09-02
found-by: frankD
summary: "`miscutils/flash_eraseall.c:50` refuses with `IR_UNSUPPORTED: frontend could not lower AST node (kind 1) -- a frontend gap, would miscompile`. THE ONLY NON-crtl REFUSAL of the fourteen at the 394-applet scope: the other thirteen are missing crtl declarations, this one is the C frontend failing to lower a node it parsed. The message is the good kind -- it refuses rather than emitting something wrong -- but it names a node KIND and not a construct, so the first job is to find out what kind 1 is. Not reproduced standalone yet."
---

# What is known

Measured 2026-09-02, busybox 1.36.1 at 394 applets, binary sha256
`32a2ce1d9806`, x86-64.

```
FAIL x86_64 miscutils/flash_eraseall.c did not become an object:
  pascal26:50: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 1)
  — a frontend gap, would miscompile
```

507 of 521 TUs compiled. Thirteen of the fourteen refusals are crtl gaps
(`feature-b-crtl-function-gaps-at-394-busybox-applets`,
`bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS`). This is the only one in
the compiler.

## First steps, in order

1. **Name kind 1.** The number is an AST node kind index; resolve it to its
   symbolic name before touching anything. A number standing in for a construct
   is the thing that makes this ticket look harder than it is.
2. **`PXXDBG=a.ast:<proc>`** on the wrapper TU rather than reasoning about the
   source — the compiler will say what it inferred, and line 50 of the wrapper
   is not line 50 of `flash_eraseall.c`.
3. Only then reduce. Five minimal programs failed to reproduce the last busybox
   finding standalone; do not assume this one shrinks either.

`--separate --applets "flash_eraseall"` plus `tools/busybox_diff.sh`'s wrapper
generator gives the exact TU in seconds; the whole 394-applet run is not needed
to iterate.

## Caveat on the line number

`pascal26:50` is a line in the generated wrapper, not in busybox's source. The
harness keeps `$WORK/wrap/miscutils_flash_eraseall.c` under `--keep` (and now,
since `1b2c0b5dc`, keeps its logs on any failure). Read the wrapper before
quoting a busybox line number anywhere.
