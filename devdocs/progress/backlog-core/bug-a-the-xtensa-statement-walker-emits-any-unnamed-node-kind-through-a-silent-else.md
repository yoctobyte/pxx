---
slug: bug-a-the-xtensa-statement-walker-emits-any-unnamed-node-kind-through-a-silent-else
track: A+S
prio: 45
type: bug
status: open
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "The xtensa statement walker's case ends in `else IREmitNodeXtensa(i)`, so ANY IR kind nobody named is emitted at statement level — and a VALUE node emitted there is also emitted by the parent that consumes it, running it twice. That is exactly how IR_VIRTUAL_CALL came to run every virtual call twice (57e35555e), and IR_ATOMIC before it. Five kinds riscv32 and arm32 both name are still absent from xtensa's list; none of them doubled in the shapes I drove, which is a measurement in those shapes and not a clearance of the catch-all."
---

# The xtensa statement walker emits any unnamed node kind through a silent `else`

`IREmitMachineCodeXtensa` walks every IR node in the body and switches on kind.
The `case` ends:

```
IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK, IR_CONST_DATA,
IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
IR_SLOTADDR, IR_FIELD, IR_INDEX: ;
{ IR_ATOMIC is a value node consumed by its parent store, like
  IR_SYSCALL. Emitting it at statement level TOO runs the
  read-modify-write twice — riscv32 and arm32 both paid for this one. }
IR_ATOMIC: ;

else
  IREmitNodeXtensa(i);
```

**The default for an unknown kind is to EMIT it.** For a statement node that is
right. For a VALUE node it is wrong twice over: the value is computed at
statement level where nothing wants it, and the parent that does want it
computes it again — so anything the subtree does, it does twice.

## This is not hypothetical; it has fired twice

- **IR_ATOMIC** — the comment above is the scar. A read-modify-write ran twice.
- **IR_VIRTUAL_CALL** — `57e35555e`, 2026-09-02. Every virtual call whose result
  was used ran its callee **twice** on xtensa, side effects and all. It reached
  the backlog as a string allocation count (7707 vs 3799) and was neither about
  strings nor about allocation.

Both were fixed one at a time, in the arm. Neither fix touched the mechanism
that will produce the third.

## What is still unnamed

Named in riscv32's and/or arm32's walkers, absent from xtensa's, therefore
reaching the `else`:

`IR_LOAD_MEM` · `IR_SET_LIT` · `IR_SET_BINOP` · `IR_SET_CMP` · `IR_DYNUNIQUE`
(plus `IR_CLONE`, `IR_ZERO_SYM`, `IR_IO_LOCK`, `IR_IO_UNLOCK` in arm32 — the last
three are statement nodes, where the `else` happens to do the right thing).

riscv32 groups `IR_SET_LIT, IR_SET_BINOP, IR_SET_CMP, IR_CONST_DATA,
IR_SLOTADDR, IR_DYNUNIQUE, IR_FIELD, IR_INDEX` into its **do-nothing** arm, which
is the shared IR saying these are value nodes.

**MEASURED, and read narrowly:** a side-effect counter driven through a set
literal containing a call, `in`, a set binop and a dynamic-array unique does NOT
double on xtensa (50 per 50 iterations, matching x86-64). That is a result about
those four shapes. It is **not** a clearance of the catch-all, and it is not a
reason to close this — the same probe run against `k := o.F(i)` before
`57e35555e` would have come back doubled, and nobody ran it for two days.

## The fix shape

Two candidates, and this ticket does not pick:

1. **Name every kind and delete the `else`** — or make the `else` an `Error`.
   Then a new IR kind fails loudly at the one place that must decide whether it
   is a statement or a value, instead of defaulting to the answer that is wrong
   for half of them. This is the `normalise-dont-special-case` answer and it
   deletes a case rather than adding one. Cost: every kind must be classified
   once, and a kind that legitimately relies on the `else` today has to be
   listed.
2. **Guard by IRStmtRoot generally** rather than per-kind — emit at statement
   level only what was marked a statement. Cheaper, but `IRMarkStatementNode`
   only marks IR_CALL / IR_VIRTUAL_CALL / IR_CALL_IND today, so everything else
   would need marking first, and that is the same enumeration by another road.

Whoever takes it should check the other backends for the same shape before
changing xtensa alone — arm32 and riscv32 have longer lists, which is not the
same as having no `else`.

## Gate

`make compiler/pascal26` plus the xtensa rows; `test_virtual_call_runs_once.pas`
is the existing regression for the IR_VIRTUAL_CALL instance and must stay green.
A fix here should come with a probe for at least one of the five unnamed kinds
that can be shown to go red if that kind were mis-emitted — a change to this
`else` that nothing can fail is not a change anyone can trust.
