---
track: A
type: bug
prio: 45
status: open
found: 2026-08-30
found-by: frankS
---

# `IROpName` names 68 of 75 IR ops, so a missing backend arm for the other seven reports `unknown`

```
error: target xtensa: unsupported node in IR codegen: unknown
```

That is the whole diagnostic. The op was `IR_CLASSREF`.

Counted by parsing `defs.inc`'s `IR_* = n;` constants against `ir.inc`'s
`IROpName` case arms, not by reading them:

| | |
| --- | --- |
| IR ops declared in `defs.inc` | **75** |
| named by `IROpName` | 68 |
| **unnamed** | **7** |

```
IR_PROCADDR(38)  IR_CLASSREF(39)  IR_VMTADDR(58)  IR_IMTADDR(59)
IR_SET_SIGNAL(65)  IR_IO_LOCK(66)  IR_IO_UNLOCK(67)
```

## Why it matters more than a cosmetic string

`IROpName` has exactly one load-bearing caller: the `unsupported node in IR
codegen` error every backend raises for an op it does not implement. So for
these seven ops the error names **nothing**, on **every** target, and the only
way to learn which op is missing is to edit the backend and self-compile.

That is not hypothetical — it is how this was found, and it cost a build. The
same shape as `target xtensa: unsupported binary operator (div/mod/shifts
pending)`, fixed on 2026-08-30 for the same reason: **a diagnostic that cannot
name its own subject makes the reader guess, and the guess is usually the
message's own stale hint.**

## Fix

Seven lines in `ir.inc`'s `IROpName`. The names are already the constant
identifiers; use the same lowercase-without-prefix convention the other 68 use
(`procaddr`, `classref`, `vmtaddr`, `imtaddr`, `set_signal`, `io_lock`,
`io_unlock`).

Worth adding with them: a compile-time or startup assertion that `IROpName`
covers every declared op, so the eighth gap cannot open silently. The count
above was produced by a parser in ten seconds; nothing in the tree runs it.

## Why filed and not fixed

`ir.inc` is shared Track A ground and a Track S stop-line.

## Bound

Static count at `f19e16b67bad`, by parsing both files. The claim that `IROpName`
has one load-bearing caller is from grepping its call sites. Not measured: how
many of the seven have a missing arm on any given backend today — only
`IR_CLASSREF` was observed to actually surface, on xtensa.
