---
summary: "Each 32-bit backend has the by-value argument ladder (Int64, double, set, 5-8 byte record) written out separately per call KIND — direct, indirect, virtual — and the virtual copy was missing the Int64 case entirely for years"
type: feature
track: A
prio: 40
---

# Unify the 32-bit call argument marshalling

- **Type:** feature (refactor) — Track A (32-bit backends)
- **Status:** backlog
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

## Gate

Track A: `make test` + self-host fixedpoint (byte-identical), plus
`tools/lib_cross_sweep.sh` A/B against the pinned stable — compare **full**
outputs, not a tail.
