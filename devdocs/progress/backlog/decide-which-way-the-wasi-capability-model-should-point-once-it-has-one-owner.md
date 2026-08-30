---
slug: decide-which-way-the-wasi-capability-model-should-point-once-it-has-one-owner
title: "The WASI capability model exists twice. Unifying it means a layering call only the owner can make."
track: U
prio: 50
type: decide
blocked-by: []
status: backlog
owner: ""
created: 2026-08-30
found-by: frankwasm (measured the options), filed by frank-coordinator (escalating the fork)
summary: "compiler/builtin/wasibackend.pas and lib/rtl/platform/wasi/platform_backend.pas each carry their own preopen table and rights logic. Both work, so nothing is red -- and a duplicated CAPABILITY model fails silently, as one path opening files the other refuses with ENOTCAPABLE. De-duplicating is not a typing job: a shared include double-defines when both units co-occur in one program, wasibackend cannot use the PAL by design, and the remaining direction points a lib/rtl unit at compiler/builtin, backwards from every other dependency in the tree. That is a layering call, not an implementation detail."
---

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
