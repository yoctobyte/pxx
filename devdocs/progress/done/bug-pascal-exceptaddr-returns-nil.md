---
prio: 35
---

# ExceptAddr is a STUB returning nil — the raise site is never recorded

- **Type:** bug (stubbed feature — declared, not implemented)
- **Track:** A — core (IR_RAISE codegen, per-backend) + B (the RTL declaration)
- **Status:** done

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

## 2026-07-14 — RESOLVED (commit eaf511e0, b340)

Done as the ticket described: each backend's raise stub records its own return address —
which IS the raise site, since the `call` to the stub pushed it — into a new
`BSS_EXC_ADDR` slot. From `[rsp]` on x86-64/i386, from the link register on arm32 (lr) /
aarch64 (x30) / riscv32 (ra), and from a0 on xtensa (call0).

The READ needed no new backend op, which is what kept this cheap: `IR_EXC_STORE` already
loads an exception BSS slot into a variable, so `IRC` just selects WHICH slot (0 = the
exception object, as `on E:` has always used; 1 = the raise address). The intrinsic
`__pxxExceptAddr` (reserved prefix — cannot collide with a user routine) emits it, and
`sysutils.ExceptAddr` is now a one-line wrapper.

Beyond the ticket: `IR_EXC_CLEAR` clears the address slot with the object and class slots.
Without that the address outlives its exception and `ExceptAddr` outside a handler returns
a stale but entirely plausible code pointer — the same silent-wrong-value shape this
codebase keeps getting caught by. nil outside a handler, as before.

`ExceptObject` / `ExceptClass` now fall out nearly free (same slots, same load); not wired
up here.

Test `test/test_exceptaddr_b340.pas`: nil before any raise; a real code address INSIDE the
routine that raised; two raise sites give two addresses; nil again after the handler.

Gate: `make test` green, self-host byte-identical, `test-i386` / `test-aarch64` /
`test-arm32` / `test-riscv32` green. The xtensa leg could not be confirmed: `test-esp-bare`'s
esp32s3 half is RED at 51968776 (before this session) too — pre-existing, filed as
[[bug-esp32s3-bare-boot-no-uart-output]].

## Log
- 2026-07-14 — resolved, commit eaf511e0.
