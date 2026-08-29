---
slug: bug-n-the-only-callers-of-evalpystmts-encode-a-contract-that-changed
title: "The 12 Pascal-side pyeval tests encode the pre-ff439149e exec() contract, fail at HEAD, and are the only callers of EvalPyStmts in the tree"
track: N
type: bug
prio: 45
blocked-by: []
status: done
found: 2026-08-29
found-by: pxx-a5 (Track T, triaging the unwired-test backlog)
owner: frankA
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

---

## Resolved 2026-08-29 — frankA

Updated to the current contract and wired, which was the ticket's first option.
The deprecation option was NOT taken, and the reason is in the code rather than
in preference: `EvalPyStmts` is the only Pascal-side entry to `pyeval`, and the
twelve tests cover material the `.npy` path does not reach from Pascal — the
host-call ABI itself, the trampoline shapes, and `Variant` marshalling across
the boundary. Deleting them would have removed the only executable description
of that ABI.

### The change is smaller than the ticket expected, and `vm` stays

The ticket says to "store the bound methods the script calls rather than a `vm`
receiver". Half of that is right. The bound methods are what was missing, but
`vm` must **stay stored**, because these scripts also reach it by ATTRIBUTE —
`vm.push(123)`, `vm.pop()`, `vm.pic.append("x")`, `vm.memory`, `vm.words`. That
is an ordinary global holding an object and always was legal; only the implicit
*host-call receiver* rule was removed. Replacing the `vm` store instead of
adding to it would have broken a different set of rows in the same files.

So each file gains, beside its existing `vm` store:

```pascal
  g.store('push', pybound_new(nil, Pointer(vm), False));
```

`code` is nil deliberately: `ParseCall`'s host path reads only
`pybound_recv(vmv)` and dispatches through `PyHostCall`'s RTTI on the receiver,
so the code pointer is never consulted for a host call. What the contract
actually requires is `pycallback_is` — tag 8 — and a recoverable receiver.

Only the names each file calls **bare** are stored, determined per file rather
than uniformly: 10 files need `push`, `bignum` needs `push,pop`, and `m1` needs
`push,pop,fpush`. A `vm.push(...)` occurrence is not a bare call and does not
count.

### Measured, both directions

| | result |
| --- | --- |
| baseline (files as committed, current compiler) | **0 of 12 pass** — every one exits 1 on its first host call, `pyeval: host call push but "push" not in globals` |
| after | **12 of 12 pass**, each printing `ALL PASS` |

The baseline run is the point: the twelve were not merely unwired, they were
*wrong*, and a "12/12 green" with no before is not evidence.

### Wired

Into `test-nilpy`, immediately after `test_nilpy_pyeval_no_vm_key.npy` — the
`.npy` test that gates the new contract on the NilPy side, so its Pascal-side
twin now sits beside it and the pair covers both entry points. Each program
`halt(1)`s on any failing row, so running it is the assertion; the recipe pins
the last line to `ALL PASS` so a program that dies silently mid-run cannot pass
by printing nothing.

`tools/check_test_wiring.py` goes from **23 unwired to 11**. The remaining 11
are `chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring`'s
scope, which this ticket blocked and no longer does — including the three
`test_o3_*` files that leave part of Track O's campaign untested.

Self-host fixedpoint unchanged by this ticket (test and Makefile only; no
compiler source touched). The 12/12 was re-measured against a binary rebuilt
after pxx-a5's `6cc4afc17` arrived in my tree via rebase: the first gate went
RED on a **stale binary**, and said so by name -- "a sibling landed a compiler
change and this checkout has not rebuilt" -- rather than presenting a
fixedpoint mismatch for me to bisect. Fixedpoint `28a17f797b64`.

## Log
- 2026-08-29 — resolved, commit bfba200a3.
