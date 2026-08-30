---
slug: decide-which-way-the-wasi-capability-model-should-point-once-it-has-one-owner
title: "The WASI capability model exists twice. Unifying it means a layering call only the owner can make."
track: U
prio: 50
type: decide
status-note: "REOPENED 2026-08-30 within hours of being decided — see EVIDENCE AGAINST THE RESOLUTION. Previously: DECIDED 2026-08-30 by the owner's standing constraint, derived by the coordinator and confirmed by measurement. Answer: C -- keep both copies deliberately, guard the drift with a differential test. Do NOT invert the layering."
blocked-by: []
status: backlog
owner: ""
created: 2026-08-30
found-by: frankwasm (measured the options), filed by frank-coordinator (escalating the fork)
summary: "compiler/builtin/wasibackend.pas and lib/rtl/platform/wasi/platform_backend.pas each carry their own preopen table and rights logic. Both work, so nothing is red -- and a duplicated CAPABILITY model fails silently, as one path opening files the other refuses with ENOTCAPABLE. De-duplicating is not a typing job: a shared include double-defines when both units co-occur in one program, wasibackend cannot use the PAL by design, and the remaining direction points a lib/rtl unit at compiler/builtin, backwards from every other dependency in the tree. That is a layering call, not an implementation detail."
---

> ## RESOLUTION, 2026-08-30 — **C. Keep both copies; guard the drift with a test.**
>
> **The owner's constraint settles the direction, and it was already on the
> record:** *"we don't want any PAL in our compiler source — since it's not
> needed. Instead we concluded to move some essentials to builtin."* That is a
> standing architectural call, not a preference, and it is the same one
> `decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`
> already acted on. Nothing in this ticket may reintroduce a PAL dependency into
> `compiler/**`.
>
> **The owner also scoped it — "it only affects a few basic file open/read/close
> primitives" — and that is measurably right**, which is what turns the fork from
> a hard call into an easy one. Measured at HEAD:
>
> | | `compiler/builtin/wasibackend.pas` | `lib/rtl/platform/wasi/platform_backend.pas` |
> | --- | --- | --- |
> | lines | 696 | 1120 |
> | duplicated logic | `WasiScanPreopens`, `WasiFindPreopen`, the rights computation, errno mapping | same |
> | what it backs | `PXXWasiOpen/Read/Write/Close/Fchmod/LoadFile/GetDents` | the full PAL surface |
>
> So the shared part is a preopen table, a rights computation and an errno map,
> behind roughly seven primitives. The PAL is a superset and does much more.
>
> **Why that scope decides it.** Options A and B each pay a permanent structural
> price — A inverts the tree's one consistent layering rule by pointing a
> `lib/rtl` unit at `compiler/builtin`; B invents a third home and must then
> answer what that home may depend on, inheriting wasibackend's constraints
> anyway. Both prices are worth paying for a large shared subsystem. Neither is
> worth paying for ~150 lines of preopen/rights logic behind seven primitives.
>
> **What the duplication actually costs is the silence, not the copying**, and a
> test removes exactly that. So:
>
> 1. Add a **differential test** asserting both implementations resolve the same
>    path to the same preopen and the same rights, including the refusal cases —
>    an `ENOTCAPABLE` one path returns and the other does not is the failure this
>    exists to catch.
> 2. **Mark the duplication as deliberate in both files**, replacing
>    `wasibackend.pas`'s header comment that currently says the follow-up
>    de-duplication is owed. That comment was right to self-report and is what
>    caught this at all; it is now wrong about the remedy.
> 3. **Do not de-duplicate.** If the shared surface ever grows well beyond these
>    primitives, reopen this ticket — that growth, not the duplication itself, is
>    the trigger.
>
> Derived rather than escalated a second time, per the coordinator's remit: the
> owner supplied the constraint and the scope, and together they settle it without
> a further judgement call.


> ### EVIDENCE AGAINST THE RESOLUTION, one day later — read before acting on C
>
> **2026-08-30, frankwasm, closing the wasmtime milestone.** A real defect was
> found in the WASI `fd_seek` path: `@WasiScratch[0]` is declared
> `array[0..15] of Byte`, `symtab.inc`'s `TypeAlign` aligns a global to its
> ELEMENT type, so the pointer was 1-aligned and landed 4-aligned by luck —
> and a strict host requires 8. **The identical defect was in BOTH copies** —
> `wasibackend`'s `fd_seek` and the PAL's `fd_seek` plus both
> `clock_time_get` calls — and had to be fixed twice, in one commit, by one
> person who happened to know both existed.
>
> **This does not confirm the drift argument; it exposes a hole in the remedy.**
> A differential test compares the two implementations against *each other*, so
> it is blind by construction to a defect that is IDENTICAL in both — a bug
> copied at birth rather than drifted into. Both copies would have agreed,
> the test would have been green, and the program would still have trapped.
>
> So the demonstrated cost of the duplication is **not** divergence. It is:
> *every fix must be applied twice, and nothing tells the second person the
> second copy exists.* frankwasm caught it only because it had just filed the
> duplication ticket. Unification removes that cost; a differential test does
> not touch it.
>
> **The resolution above is therefore NARROWER than it reads.** C's test is still
> worth building — it catches divergence, which is a real and different failure —
> but it must not be recorded as closing this question. The owner should see this
> evidence before C is treated as final, since the scope argument ("only a few
> primitives") was what made C comfortable, and this defect shows the cost is
> paid per-FIX rather than per-line.
>
> Raised by the coordinator rather than silently kept, 2026-08-30.

# What is being asked

`bug-a-two-copies-of-the-wasi-capability-model-one-in-the-pal-one-in-wasibackend`
[A p50] is real and should be fixed. **This ticket is only about which
direction the fix points**, because that choice is a standing constraint on the
tree's shape and outlives the bug.

## Why the obvious answers are already closed

frankwasm measured these rather than reasoning about them, while closing
`feature-a-wasm32-sys-intrinsics-and-ir-syscall-lowering`:

- **A shared `{$include}` does not work.** Both units can legitimately co-occur
  in one program — a raw `sysopen` alongside `uses SysUtils` — and a textual
  include then double-defines every symbol.
- **wasibackend cannot use the PAL.** That is the whole point of the unit: the
  compiler bootstraps on intrinsics precisely so it does not carry an RTL
  dependency, which is what
  `decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`
  settled when it chose a separate injected builtin over linking the PAL.

## The fork

| option | what it costs | what it buys |
| --- | --- | --- |
| **A. `platform_backend` delegates to `wasibackend`** | a `lib/rtl` unit depends on `compiler/builtin` — backwards from every other dependency in the tree. Feasible (`builtin/` is a search directory), but it makes the RTL depend on the compiler's private support unit | one owner, one table, smallest diff, no new home to place |
| **B. a third unit both depend on** | reopens what *that* unit may depend on, and it must be reachable from a program that links no PAL — i.e. it inherits wasibackend's constraints anyway | correct layering; the shared thing sits below both |
| **C. keep both copies, add a differential test** | the duplication stays, and so does the drift risk in principle | cheap, fast, and converts the *silent* failure into a red test. A guard that CAN fire, unlike the header comment that is the only guard today |
| **D. do nothing** | the next divergence is discovered as a user-visible `ENOTCAPABLE` on one path only | nothing |

## Recommendation

**C now, then B — and explicitly not A.**

The thing that makes this bug dangerous is not that the code exists twice; it is
that the two copies can disagree *silently*. A differential test that asserts
both preopen tables answer identically for the same input removes the danger in
an afternoon and does not spend a layering decision to do it. That is the same
shape as `bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`
in reverse: build the guard that can actually fail.

**A is the option to be most careful about**, because it is the smallest diff and
will therefore keep looking attractive. Pointing `lib/rtl` at `compiler/builtin`
inverts the tree's one consistent layering rule to save one file, and every later
reader has to learn the exception. If the owner is comfortable with that
inversion, say so explicitly and it becomes cheap and fine — the cost is the
precedent, not the edit.

**Not decided here, deliberately:** whether B's third home lives under `lib/rtl`,
under `compiler/builtin`, or somewhere new. That question only becomes real once
the owner rules that B is the target.

## Note on why this is a U ticket and not just work

Per CLAUDE.md's Track U rule — escalate, don't guess. The de-duplication itself
is ordinary Track A work with an obvious mechanism; it is *which way the
dependency points* that cannot be settled from the code, the request, or a
sensible default, because the tree has exactly one convention here and every
option either breaks it or invents a new place.
