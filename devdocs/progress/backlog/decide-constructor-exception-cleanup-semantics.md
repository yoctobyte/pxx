# DECIDE: constructor-exception-cleanup semantics (auto-Destroy on failed Create?)

- **Type:** decision (language semantics / FPC-compat) — Track A
- **Status:** backlog — no implementation yet; capturing the design
  discussion so whoever implements constructor codegen starts from the
  recorded trade-off instead of silently picking one.
- **Opened:** 2026-07-04, from a user discussion on `class of` / metaclasses
  that drifted into constructor-failure cleanup.

## Upstream (FPC/Delphi) behavior

Every constructor body is implicitly wrapped by the compiler in a
try/except: if an exception escapes the constructor, the runtime calls
`Destroy` on the partially-constructed instance (memory is already live —
`NewInstance` ran before the constructor body), then re-raises to the
caller. This is unconditional — every constructor gets the wrapper whether
the class needs it or not. Its corollary: a destructor written against this
contract must tolerate being invoked on a half-initialized object (nil
fields it never got to set), which is why idiomatic Pascal destructors guard
every free/dispose with `if Assigned(...)`.

## Position recorded (2026-07-04 discussion)

- **User**: raising from inside `Create` is itself a bad habit — if a
  constructor throws, the code calling it (or the constructor itself) is
  wrong, and a compiler papering over that with implicit cleanup boilerplate
  is solving a problem well-written code shouldn't create. Prefers no
  implicit try/except wrapper: cheaper codegen, consistent with this
  project's general stance of not inserting safety nets for cases that
  shouldn't happen ([[frank2-platonic-no-workarounds]] in spirit — sloppy
  code is a bug, not the runtime's job to catch).

## Options on the table

1. **Match FPC exactly**: implicit try/except-call-Destroy-reraise wrapper
   on every constructor. Needed only if source/binary compat with existing
   Pascal code that leans on this (rare — old libs doing multi-stage
   resource alloc across one constructor) matters.
2. **No wrapper** (current lean): constructor exception propagates raw, no
   auto-Destroy. Cheaper codegen, matches the project's no-implicit-safety-net
   stance. Breaks compat with the rare upstream code relying on the cleanup
   contract.
3. **Opt-in wrapper**: directive/switch to request FPC-parity behavior per
   unit or per class, defaulting off.

## Acceptance (of the decision, not code)

A written choice (2, almost certainly, per the discussion) recorded here;
if anything ever surfaces requiring FPC-parity cleanup semantics, revisit
before implementing rather than assuming option 2 forever.
