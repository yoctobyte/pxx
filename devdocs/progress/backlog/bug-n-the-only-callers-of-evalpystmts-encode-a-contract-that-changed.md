---
slug: bug-n-the-only-callers-of-evalpystmts-encode-a-contract-that-changed
title: "The 12 Pascal-side pyeval tests encode the pre-ff439149e exec() contract, fail at HEAD, and are the only callers of EvalPyStmts in the tree"
track: N
type: bug
prio: 45
blocked-by: []
status: backlog
found: 2026-08-29
found-by: pxx-a5 (Track T, triaging the unwired-test backlog)
---

# The only callers of `EvalPyStmts` encode a contract that changed under them

Found by Track T while triaging
[[feature-t-fail-when-a-test-file-is-wired-into-no-build-rule]]. **T owns the
tool, never the bug** — filed here because the subject is `pyeval`'s exec
contract.

## Measured

All 12 `test_pyeval_*.pas` build cleanly at HEAD `f576ec79d` (self-hosted binary
`5c9d52bdd0bf`, fixedpoint verified) and **exit 1 on the first host call**:

```
pyeval: host call push but "push" not in globals
pyeval: host call pop  but "pop"  not in globals
```

Not a regression — a **deliberate contract change they were never updated for.**
`ff439149e` ("exec() host-call reads receiver from the bound method, not a
hardcoded `vm` key") replaced

> the receiver is a global named `vm`

with

> the receiver is carried by the bound method the callee resolves to
> (`env = {"push": b.push}`)

which was correct: the old rule was uforth's own variable name leaking into the
general `exec()` contract, and any caller whose env had no `vm` key failed with
a message naming an identifier it never wrote
(`bug-pyeval-exec-requires-a-globals-key-named-vm`). The 12 tests all do
`g.store('vm', vmv)` and then call bare `push(...)`, which is exactly the shape
that fix removed.

## Why nobody noticed, and why it is worth a ticket rather than a delete

`ff439149e` touched three files: `compiler/builtin/pyeval.pas`, a **new**
`test_nilpy_pyeval_no_vm_key.npy`, and the `Makefile` line wiring that new test.
So the change shipped with a test for the new contract and left the twelve
existing tests for the old one — **unwired, so nothing ran them, so nothing said
they had stopped meaning anything.**

And the reach is larger than twelve files:

> **Those twelve are the only callers of `EvalPyStmts` / `EvalPyExpr` anywhere
> in the tree** — no example, no library, no other test. So the Pascal-side
> entry point to `pyeval` currently has zero live users and zero running tests,
> and the `.npy` test that gates the new contract exercises the NilPy-side path
> only.

That is the part that makes this a bug rather than housekeeping: the API is not
merely untested, it is untested *and* every artifact that would have shown it
broken was invisible to the harness.

## What the fix looks like

Update each one to the current contract — store the bound methods the script
calls (`push`, `pop`) in the globals dict rather than a `vm` receiver — then
wire them. They are otherwise substantive: `def`/`return`, closures over the
to_cell idiom, early return from loops, local-scope isolation, nested calls,
f-strings, slices, `is`/`in`, bignums, `isinstance`/`del`, memory/bytes, and the
trampoline shapes. Rewriting the harness lines revives real coverage.

If the answer is instead that the Pascal-side `EvalPyStmts` entry point is
deprecated in favour of the `.npy` path, that is a legitimate outcome — but then
it should be *said*, the files deleted, and the entry point marked, because the
current state reads as "twelve tests cover this" to anyone who greps.

## Track

N owns the exec contract (`ff439149e` is `fix(nilpy)`; `c2c0e79e0` is `fix(N)`).
`compiler/builtin/pyeval.pas` is physically A's file-lane, so if N reads this as
A's change, re-file it there — the contract is the deliverable, not the letter.

## Gate

Per CLAUDE.md's per-fix loop: `make compiler/pascal26` plus the repro. Do not
widen it; Track T sweeps the matrix.
