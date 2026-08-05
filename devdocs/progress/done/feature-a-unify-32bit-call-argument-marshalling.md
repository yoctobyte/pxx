---
summary: "Each 32-bit backend has the by-value argument ladder (Int64, double, set, 5-8 byte record) written out separately per call KIND — direct, indirect, virtual — and the virtual copy was missing the Int64 case entirely for years"
type: feature
track: A
prio: 40
owner: agent-ap-night4
---

# Unify the 32-bit call argument marshalling

- **Type:** feature (refactor) — Track A (32-bit backends)
- **Status:** done
- **Opened:** 2026-08-05
- **Prompted by:** [[bug-a-virtual-method-int64-in-and-out-32bit]], which was
  exactly this drift and was silent on arm32/riscv32 and a segfault on i386.

## The shape

`ir_codegen386.inc`, `ir_codegen_arm32.inc` and `ir_codegen_riscv32.inc` each
push call arguments with a ladder of by-value special cases:

- 64-bit scalar (`Int64`/`UInt64`) — two words
- `double` — two words; `single` — one, narrowed first
- `set` — eight words, pushed inline
- by-value record of 5-8 bytes — two words
- variadic tail 64-bit / double — two words

and each backend writes that ladder out **once per call kind**: `IR_CALL`
(direct), the external-C path, the indirect proc-var path, and
`IR_VIRTUAL_CALL`. Three backends x four kinds. They are not identical, and
they were never meant to differ.

`IR_VIRTUAL_CALL` had **no ladder at all** in any of the three — one word per
argument, unconditionally. That is the bug above, and it was not the only thing
missing: the by-value `set` case was wrong too (`CountSet([eA,eC,eD])` answered
1 on i386 and 0 on riscv32 where FPC says 3), found by testing this ticket's
prediction rather than assuming it. Both are fixed and tested now. What remains
is that the copies still differ in which cases they carry — the virtual paths
handle 64-bit, double and set; the direct paths also handle 5-8 byte records
and variadic tails — and nothing keeps them in step.

## The ask

Extract one `EmitCallArgWords<arch>(argNode, procIdx): Integer` per backend
(returning the word count) and call it from all four sites. The per-arch
instruction emission stays where it is; what unifies is the **decision** about
how many words each parameter occupies, which is ABI logic and identical across
call kinds by definition.

Better still, that decision is target-independent — "does param i of proc p take
one word or two on a 32-bit target" — so it could be one shared helper in
`symtab.inc`/`ir_codegen.inc` that all three backends consult, with only the
push emission per-arch. That would make a future 32-bit target correct by
construction.

## Test the shapes that have no coverage

`test/test_virtual_int64_param_and_result.pas` now covers 64-bit and set
through a virtual call on all five targets. A 5-8 byte by-value record through
a virtual call is still untested; it happens to work today because every
backend passes such records by address on the virtual path, which is a
coincidence rather than a decision.

## What was actually done (2026-08-05)

The decision was extracted to `Arg32Class` / `Arg32Words` in `symtab.inc` —
target-independent, consulted by all three 32-bit backends and by all three call
kinds. Emission stays per-arch, and riscv32 additionally got one
`EmitCallArgWordsRISCV32` shared by its three sites.

**Writing the matrix test FIRST is what made this worth doing.** The ticket
predicted drift; `test/test_call_arg_marshalling_32bit.pas` measured it, and the
prediction was understated — four more silent holes were live at HEAD:

| backend | call kind | missing case | symptom |
| --- | --- | --- | --- |
| i386 | virtual | `double` | `o.VDbl(1, 6.0, 9)` = 840500009, want 169 |
| i386, arm32 | virtual | `single` | `o.VSgl(1, 6.0, 9)` = 109, want 169 |
| i386 | indirect | by-value `set` | `pS(1, [eA,eC,eD], 9)` = 838829819, want 139 |
| riscv32 | indirect | Int64, double, set | no ladder at all — "scalar word args only" |

riscv32's indirect path also needed the >8-word stack spill its direct and
virtual paths already had (one scalar plus a set is nine words); it used to
refuse outright.

Every case sandwiches the wide argument between plain Integers on purpose — a
wrong word count usually does not corrupt the wide value, it SHIFTS every
following argument, so a trailing Integer is the sensitive detector.

**Two deliberate non-changes**, both documented at the helper:

- The **5..8 byte by-value record** stays out of the shared classifier. Only
  riscv32's direct path treats it as a pair; the other eight paths pass it by
  address and all agree with FPC today. Folding it in would change eight working
  paths to match one. Still untested-by-design territory, still the ticket's
  open question.
- A **Single in a variadic tail** stays one word rather than promoting to double
  as C varargs would. That is what every path does today; whether the promotion
  is missing is a separate question from whether the ladders agree, and folding
  a behaviour change into a de-duplication is how a refactor gets blamed for a
  bug it did not cause.

`arm32` keeps passing by-value sets by ADDRESS (caller and callee agreeing),
which is why it was the one backend the virtual-set bug never hit. The shared
helper decides the CLASS; each backend still owns its ABI.

## Gate

Track A: `make test` + self-host fixedpoint (byte-identical), plus
`tools/lib_cross_sweep.sh` A/B against the pinned stable — compare **full**
outputs, not a tail.

## Log
- 2026-08-05 — resolved, commit caf09e540.
