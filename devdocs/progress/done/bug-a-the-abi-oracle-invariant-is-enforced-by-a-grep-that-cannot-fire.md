---
slug: bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire
title: The ABI oracle's invariant is enforced by a review grep that matches nothing
track: A
type: bug
prio: 45
status: done
found: 2026-08-28
found-by: frankwasm (hit it in the wasm backend), generalised and verified by frank-coordinator
owner: frank-rust
summary: "DONE 2026-08-31. The invariant is now enforced by `tools/abi_oracle_lint.py`, which detects the SHAPE (an ABI-carrying Syms[] field combined with a type-kind test, for a parameter, across line breaks) rather than the spelling `IsRef or`, and which carries 8 asserted self-controls including one proving its routine-scoped exemption cannot leak past the next routine header. abi.inc's dead clause is replaced and now points at the tool. NOTE the grep had got WORSE than the ticket recorded: by 2026-08-31 it matched 1 line, a COMMENT quoting the rule — a reviewer gets a hit, opens it, finds prose, concludes clean. Audit: 78 raw hits -> 22 (parameter questions only) -> 6 (after exempting EmitParamSpillsForTarget, which asks slot WIDTH, a question the oracle does not answer) -> 1. Five sites are real, stated divergence, marked `abi-divergence:` — four depend on InLValueWrite, which the oracle's symIdx-only signature cannot see, and one sits INSIDE the oracle's own then-branch. The remaining 1 is a genuine disagreement, escalated as bug-a-aarch64-setlength-on-a-frozen-string-param-diverges-from-the-abi-oracle. The linter deliberately still exits 1, so it is NOT wired into a gate: a green baseline here would be the false zero this ticket exists to complain about."
---

## The fact

`compiler/abi.inc` states its invariant plainly, and then names its own enforcement:

> **Backends consult the oracle and never re-derive the convention from `Syms[]`.**
> That clause is greppable in review: a `Syms[...].IsRef or` chain inside
> `ir_codegen*.inc` means someone grew a ninth copy.

Measured on today's master:

```
$ grep -rn "IsRef or" compiler/ir_codegen*.inc | wc -l
0
```

**The declared review clause matches nothing, and has no way to fire.** A reviewer who
runs exactly the grep the file tells them to run gets a clean result, forever, on any
tree — including one where the convention has been re-derived in every backend.

Meanwhile the convention *is* re-derived longhand, just not with the word `or`.
`ir_codegen_riscv32.inc:1549-1566` decides `IR_LEA`'s parameter-address question — which
is verbatim the question `ABIParamSlotHoldsValueAddr` exists to answer (*"Asked by every
backend when it needs the address of a parameter"*) — with a hand-written chain over
`IsArray`, `IsRef` and `TypeKind = tyAnsiString`, spelled `and ... and not`. Same shape at
`:2419`. The grep cannot see either.

## What this is NOT

Not "abi.inc failed." It consolidated eight copies and every backend consults it (1-3
call sites each; none ignores it wholesale). The oracle is doing its job at the sites that
call it.

Not "riscv32 is broken." Those sites are heavily commented, each cites a ticket, and
`abi.inc`'s own header says targets need not agree with each other. They may all be
correct today.

**The defect is that nothing can tell the difference.** The file predicted its own failure
mode — *"no test would have caught a ninth drifting"* — proposed a grep against it, and
the grep was calibrated to a spelling rather than to the shape. Drift has since begun and
the detector reports clean.

## Why it is p45 and not a style ticket

frankwasm paid the real cost in the wasm backend, and the symptom is the expensive kind:

> A frozen VALUE parameter is passed as the address of a buffer on every target, and the
> flag saying so lives on the parameter's **SYMBOL**, not on the proc's declaration
> record. Reading the wrong one made `const x: ShortString` come back with **"no wasm
> value type"** — so the callee and every call site went unreachable.

**A missing CONVENTION reported as a missing TYPE.** The next person follows the message
and goes looking for a type mapping that does not exist. Two calls to the oracle fixed it,
and by-value copy semantics came free — which is the oracle working exactly as designed,
for a backend that had not asked it.

The oracle's stated success metric is that a new pass-by-pointer kind costs one edit.
**The corollary nobody wrote down is that a backend which does not consult it gets the
wrong answer silently, and no gate can see that.**

## The fix

Not "remove the riscv32 chains" — first make the invariant checkable, then use it to find
out whether they are drift or deliberate divergence.

1. **Replace the grep with something that can fail.** The shape to detect is
   *a type-kind test combined with `IsRef`/`IsArray` inside `ir_codegen*.inc`*, not the
   token `or`. A ~20-line script in `tools/` beside `forwardlint.py` is the right size; it
   must produce a **non-empty baseline today** and be reviewed down to zero, because a new
   check whose first run is clean has proved nothing.
2. **Audit the sites it finds.** For each: does it ask a question the oracle answers? If
   yes, call the oracle. If it is a deliberate per-target divergence, it belongs in the
   oracle's table where `abi.inc` says divergence should be *"deliberate and reviewable
   instead of accidental and invisible."*
3. `ir_codegen.inc` has the most type-combined sites (21) and also consults the oracle
   most. Expect the highest false-positive rate there; do not let that stall the pass.

`ir_codegen_wasm32.inc` is **not on master** (branch only), so its two instances are not in
the counts above. It will arrive with the merge.

## Related

Same generator as `bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open` and
`bug-p-an-unknown-compiler-directive-is-silently-ignored`: **a check or a chain whose
failure case is unreachable, so its silence carries no information.** Third structural
instance this week. A check that cannot fail and a check that is passing are the same
observation, and only one of them is worth anything.

---

## The same disease with a second mechanism — verified 2026-08-28

`bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64` [A, p70] is this ticket's
problem wearing a different failure mode, and the pair is worth reading together because the
fix shape is shared.

**Counted directly** (`grep -n IRNodeOwnsManagedStr compiler/ir_codegen*.inc`):

| backend | binop sites asking the ownership predicate |
| --- | --- |
| aarch64, arm32, riscv32, i386 | **3 each** (concat, equality, ordered) |
| x86-64 (`ir_codegen.inc`) | **1** |

Result: `if F(x) = 'lit'` leaks F's result **on the default target**, every evaluation, `-O0`
and up, silent and unbounded — 40 bytes an iteration, measured.

**The distinction that makes this pair instructive:**

- **This ticket**: an oracle exists (`abi.inc`) and backends **re-derive instead of asking**.
- **That ticket**: an oracle exists (`IRNodeOwnsManagedStr`, one function) and a backend
  **forgets to ask at one of the sites where asking is required**.

Both are **an obligation across a backend × site matrix with nothing enforcing completeness**,
and in both cases a grep for the predicate's *name* returns plenty of hits and tells you
nothing — the defect is a hit that is **absent**, which is the family's signature.

**The mirror is already in `done/`.** `bug-a-a-string-function-result-in-a-concat-leaks-on-
every-cross-target` fixed the *opposite* half — predicate right on x86-64, missing from the
four cross backends — and its own comment observed *"this was the FIFTH hand-written copy of
that predicate."* It fixed the copies without removing the need for copies, so the other half
of the same fifteen-cell matrix stayed broken and nothing noticed for months.

**So neither ticket may be closed by adding more call sites.** Closing this family means one
of: a completeness check over the matrix, or a shape where the obligation cannot be omitted
(the predicate asked once at the shared layer, backends receiving the answer). Six more copies
and no note about the sixteenth is the failure this pair documents.

---

# RESOLVED 2026-08-31 — frank-rust

## The grep had rotted further than the ticket recorded

The ticket measured `grep -rn "IsRef or" compiler/ir_codegen*.inc | wc -l` as
**0**. On 2026-08-31 it is **1**, and the one hit is
`ir_codegen_wasm32.inc:1736` — **a comment quoting this very rule.**

That is strictly worse than zero, and it is worth stating because it inverts the
ticket's own framing. A reviewer who runs the prescribed grep now gets a
non-empty result, opens it, finds prose describing the shape to avoid, and
concludes the check ran and the tree is clean. **The dead check acquired a
false positive that reads as evidence it works.**

## What replaced it

`tools/abi_oracle_lint.py`. It asks the shape's question: does one boolean
condition in `ir_codegen*.inc` combine an ABI-carrying `Syms[]` field
(`IsRef`/`IsArray`) with a type-kind test, **for a parameter**? Conditions are
followed across line breaks to their `then`/`do`, because the real chains wrap —
which is the other half of why a line-oriented grep could not see them.

**Eight self-controls, all asserted (`--selftest`).** The ones that earned their
keep:

- the shape in the spelling the old grep *could* see (`IsRef or`), and in the
  spelling that defeated it (`and ... and not`, wrapped over two lines);
- the real wasm32 comment above — must NOT be reported, which is what proves the
  comment stripper works on the exact line that fooled the old check;
- a routine-scoped exemption must silence the routine it heads **and must not
  leak into the next one**. That control is the one I would have skipped and it
  is the one guarding the mechanism most able to hide a real hit.

## The audit, and why the funnel matters more than the endpoint

| stage | hits | what was removed |
| --- | --- | --- |
| raw shape | 78 | — |
| parameter questions only | 22 | IR_STORE type dispatch; `skLocal` finalisation |
| after one routine exemption | 6 | `EmitParamSpillsForTarget` (17 sites) |
| after stating real divergence | **1** | five sites marked `abi-divergence:` |

**The first number was a trap I nearly shipped.** 78 is a satisfying baseline
and most of it could never have been an oracle call — local finalisation and
store-lowering type dispatch. A linter whose hits are mostly noise gets muted,
which reaches the same end state as one that cannot fire, just more slowly. The
narrowing came from reading `abi.inc`'s own words — *"does a PARAMETER's stack
slot hold the ADDRESS OF THE VALUE"* — rather than from tuning until the number
looked right.

`EmitParamSpillsForTarget` is exempted with a stated reason, not silenced: it
asks the **slot width / register class** question, which the oracle does not
answer, and it already delegates correctly (`ABIParamSlotIsPointer`, three call
sites) where the oracle's question does come up. That is 17 of the 22 and the
ticket predicted it — *"expect the highest false-positive rate there"*.

## The five marked sites are divergence with a reason, not rubber stamps

Four (riscv32 `:1674 :1685`, xtensa the same two) turn on **`InLValueWrite`**,
and `ABIParamSlotHoldsValueAddr(symIdx)` **takes only a symIdx** — the oracle
cannot see lvalue-write context, so the question is genuinely outside the table.
Both chains call the oracle as their final arm. The fifth
(`ir_codegen.inc:6341`) is nested **inside** `if ... ABIParamSlotHoldsValueAddr
then`: the oracle has already answered, and the arms only refine how many
dereferences follow.

If the oracle ever grows a write-context parameter, those four collapse into it.
That is the real follow-up and it is not free, which is why it is named here
rather than done quietly.

## The one that is left, and why it stays red

`ir_codegen_aarch64.inc:2869` re-derives the question with `... and not
IsArray`, where the oracle returns True when `IsArray` is set. Filed as
[[bug-a-aarch64-setlength-on-a-frozen-string-param-diverges-from-the-abi-oracle]]
with the truth table. I did **not** build a repro and do not claim it is
reachable — the fix is one line either way, and which line depends on that.

**The linter is deliberately NOT wired into `gate.sh`.** Wiring it today would
mean either a red gate or marking that site to make it green, and marking a site
I have not resolved to obtain a green baseline is precisely the false zero this
ticket exists to complain about. It is one line in `gate.sh` the day that ticket
closes.

## Scope note

This closes the `abi.inc` half of the pair. The `IRNodeOwnsManagedStr` half
recorded at the foot of this ticket is a **different oracle with the same
disease** and is untouched: the completeness check built here does not detect a
*missing* call, which is that half's signature. It needs its own instrument, and
the funnel above is the argument for building it around the question rather than
the identifier.

## Log
- 2026-08-31 — resolved, commit bd909ff64.
