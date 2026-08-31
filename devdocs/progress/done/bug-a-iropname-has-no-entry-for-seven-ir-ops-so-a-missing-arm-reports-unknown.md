---
track: A
type: bug
prio: 45
status: done
found: 2026-08-30
found-by: frankS
owner: frank-rust
summary: "DONE 2026-08-31. All seven ops named in ir.inc's IROpName (procaddr, classref, vmtaddr, imtaddr, set_signal, io_lock, io_unlock); 75/75 by an independent parse. The assertion the ticket asked for exists and is wired: tools/iropname_lint.py, in gate.sh, sub-second, 4 asserted self-controls. Verified end-to-end by A/B against pinned on `--threadsafe hello` with PXXDBG=a.ir:* — pinned prints 80 `unknown`, HEAD prints 40 io_lock + 40 io_unlock. NOTE the linter's first version was WRONG in the house style: it scanned the case body including COMMENTS, and my own new comment names IR_CLASSREF, so deleting that arm left it reporting clean. Caught by a real-tree positive control, not by the unit selftest. Comment stripping added plus a control for exactly that. Also corrects the now-stale comment at ir_codegen_xtensa.inc:3391, which still said IROpName has no entry for classref."
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

---

# RESOLVED 2026-08-31 — frank-rust

Seven arms added; an independent parse of `defs.inc` against `ir.inc` now gives
**75 declared, 75 named, 0 unnamed**. The count was re-derived rather than taken
from the ticket, and matched it exactly.

## The assertion the ticket asked for exists and is wired

> *"Worth adding with them: a compile-time or startup assertion that IROpName
> covers every declared op... The count above was produced by a parser in ten
> seconds; nothing in the tree runs it."*

`tools/iropname_lint.py`, wired into `gate.sh`. Sub-second, parses two files,
builds nothing. **"Nothing in the tree runs it" was the whole defect** — the
parser already existed as a one-off; what was missing was a caller.

## End-to-end, against pinned

`PXXDBG=a.ir:*` on `--threadsafe hello.pas`, which emits `IR_IO_LOCK` /
`IR_IO_UNLOCK`:

| | `unknown` | `io_lock` | `io_unlock` |
| --- | --- | --- | --- |
| `pinned` | **80** | 0 | 0 |
| HEAD | 0 | **40** | **40** |

40 + 40 = 80 exactly, which is what makes it an identity rather than two numbers
that happen to differ.

## My first linter had the exact bug it was written to catch

The first version scanned the `case` body for `IR_*` tokens **including
comments** — and the comment I had just written above the seven new arms names
`IR_CLASSREF`. So deleting the `IR_CLASSREF` arm left the linter reporting
**clean**.

That is `abi.inc`'s dead review grep, reproduced from scratch, hours after I
replaced it: **a checker satisfied by prose.** And it arrived by the same route
frankwasm identified — *the better the surrounding comment, the more convincing
the dead check becomes.* Writing a careful comment is what broke it.

**The unit selftest did not catch it.** Its synthetic fixtures had no comments,
so it passed while the tool was blind on the real file. It was caught only by a
real-tree control — delete a real arm, assert the file actually changed, then
require exit 1. Comment stripping and a `comment_only` control are now both in.

The transferable bit: **a selftest over synthetic fixtures tests the logic, not
the input.** The fixture is written by the same person with the same blind
spot, so it inherits the assumption instead of challenging it. Run the control
against the real file.

## Also fixed

`ir_codegen_xtensa.inc:3391` said IROpName has no entry for this op — true when
written, false as of this commit, and it sits directly above the arm that exists
because of it. Rewritten to past tense with the resolution rather than deleted:
the original diagnostic is why that arm exists.

## Log
- 2026-08-31 — resolved, commit 60f0f1982.
