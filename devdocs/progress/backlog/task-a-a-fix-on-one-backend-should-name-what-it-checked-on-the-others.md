---
slug: task-a-a-fix-on-one-backend-should-name-what-it-checked-on-the-others
track: A
prio: 40
type: task
status: backlog
found: 2026-08-30
blocked-by: []
summary: "Three fixed-on-one-target-left-on-the-others defects surfaced in one night, all by the same mechanism: a fix is written where the bug was observed, and the sibling backends have no observer. normalise-dont-special-case.md already says to grep for the sibling before closing; it is not being followed, and one of the three shows why -- the unfixed sibling's own comment ADMITTED the gap and nothing routed a reader to it."
---

# A fix on one backend should name what it checked on the others

Not a bug — a **process gap with three receipts from a single night**, filed so the fourth
instance is recognised as an instance rather than triaged from scratch.

## The three

| # | fixed on | left on | tell |
| --- | --- | --- | --- |
| 1 | `xtensaenc.inc` range-checks four PC-relative forms through one helper | **`rv32enc.inc` masks every offset and contains no `Error(` at all** | `bug-a-riscv32-pc-relative-encoders-silently-truncate-xtensa-already-guards` [A+S p60] |
| 2 | x86-64 `ArgStr` bounds-checks against `argc` in `EmitArgvToStringManaged` | riscv32 and xtensa read past `argv` **into `envp`** and return an environment string | `bug-a-argstr-reads-past-argv-into-the-environment-on-riscv32-and-xtensa` [A+S p45] |
| 3 | `PXXSysRead` had riscv32 + xtensa arms | `PXXSysOpenRO` / `PXXSysLseek` / `PXXSysClose` had neither; `{$else}` returned −1 | `bug-a-loadfile-runtime-wrappers-have-no-riscv32-or-xtensa-arm` [A p45] |

Case 1 has been paid for **twice already**: riscv32's `IR_JUMP_IF_FALSE` emits bne-skip + jal
because a bare `beq` truncated and branches landed inside unrelated code (chess perft counted
164), and xtensa's version cost a disassembly and the arithmetic `262591−262144=437`. **Both
times the call site was worked around or one encoder was guarded, and the other encoder was
left sharp.**

## The mechanism, and it is not carelessness

**A fix is written where the bug was observed, and the sibling backends have no observer.**
x86-64 is exercised by every developer on every run; the cross arms are exercised by a sweep
that reports pass/fail, not **parity**. So each divergence looks local, accumulates silently,
and is discovered years apart by its own symptom rather than by review — which is exactly what
happened to case 1 twice.

Case 3's tell is the sharpest diagnostic available for this class: **one sibling had the arms
and three did not.** A deliberate decision applies to a family; drift applies to whichever
member someone was standing next to.

## Why the existing instruction is not enough

`devdocs/dev/normalise-dont-special-case.md` already says: *if you fix a bug on one arm of a
double case, grep for the sibling before closing the ticket.* Three instances in one night says
it is not being followed, and **case 2 shows the reason**: riscv32's own comment *admitted the
gap* — "or junk past envp for a huge index" — and nobody read it, because **nothing routes a
reader from the fixed arm to the unfixed one.** An instruction that fires only when someone
remembers to look is not a mechanism; it is a hope with a document around it.

Note too that case 2's xtensa port was **faithful to riscv32 and unfaithful to x86-64**. Copying
the nearest sibling propagates the divergence and looks like consistency while doing it.

## The change asked for

Small, and deliberately not a tool: **a fix that lands on one backend names what it checked on
the others, in the close** — including **"did not check"**, which is at least a fact the next
reader can act on. Absence of the line currently reads identically to "checked and they were
fine", which is the ambiguity doing the damage.

Whether this becomes a `progress.sh check` aperture is a separate question and probably a later
one — the population (does this ticket touch a per-backend file?) is inferable from the diff,
but a check that cries wolf gets scrolled past, so measure before ratcheting. Start with the
convention.

## Gate

No code. Landed when the convention is written where a closer will meet it —
`devdocs/dev/normalise-dont-special-case.md`, beside the existing sentence it is strengthening,
not in a new document.
