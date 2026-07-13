---
prio: 35
---

# ExceptAddr is a STUB returning nil — the raise site is never recorded

- **Type:** bug (stubbed feature — declared, not implemented)
- **Track:** A — core (IR_RAISE codegen, per-backend) + B (the RTL declaration)
- **Status:** backlog — opened 2026-07-13 while landing fpcunit's chain.

## What it is now
`lib/rtl/sysutils.pas` declares `function ExceptAddr: Pointer` and **returns nil**. It
is declared because FPC code calls it (fpcunit's `AddFailure(..., ExceptAddr)`), and a
nil is *defensible there* — its callers are diagnostic, and fpcunit's `AddrsToStr`
prints `n/a` for a nil address, so nil lands on the unit's own sanctioned "no address
known" path rather than lying with a plausible-looking pointer. Pass/fail is unaffected.

It is still a stub, and the comment at the declaration says so. This ticket exists so
it does not quietly become folklore that "ExceptAddr works".

## Why the real fix is cheap
The information is already on the stack at raise time:

- `IR_RAISE` codegen already stores the exception object and class into BSS slots
  (`BSS_EXC_OBJ` / `BSS_EXC_CLS`) before calling the raise stub;
- the `call` to that stub **pushes the raise site itself** — at stub entry, `[rsp]` IS
  the address just after the `raise`.

So the raise stub can store its own return address into a new `BSS_EXC_ADDR` slot, and
`ExceptAddr` becomes a load of it. Per-backend, but each is a couple of instructions,
and it mirrors what the object/class stores already do.

Care: the slot must be captured per raise, and nested/re-raise must overwrite it in the
same order the object slot does — whatever discipline BSS_EXC_OBJ already follows, this
follows.

## Also worth having once the address exists
`ExceptObject` / `ExceptClass` (FPC System) read the same BSS slots and would fall out
nearly free.

## Gate
`make test` + self-host byte-identical + cross (it touches per-backend raise codegen).
