---
track: A
prio: 45
type: refactor
blocked-by: []
status: new
owner: ""
found: 2026-08-30
found-by: frank-optimize, closing out bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64
summary: "IRNodeOwnsManagedStr — 'does this node hand over a +1 reference the consumer must release' — is asked at ~25 hand-written call sites across five backend files. The repo has now been wrong at BOTH ends of that matrix: the predicate was missing from four cross backends (concat) and separately missing from x86-64 (comparison). Each half was found by a heap measurement, months apart, and neither by a test. x86-64 now routes its five comparison sites through one shared helper; the four cross backends still hand-write it 6-7 times each."
---

# The owned-string release predicate is hand-copied across five backends

## The pattern that produced two bugs

`IRNodeOwnsManagedStr(n)` answers *"does this node hand over a +1 reference, so
the consumer must release it"*. Every emitter that consumes a managed-string
operand must remember to ask it. Nothing enforces that it does; forgetting is
silent, produces correct output, and leaks proportionally to how often the
expression is evaluated.

It has now been forgotten at **both ends of the same matrix**:

| ticket | missing from | found by |
| --- | --- | --- |
| `bug-a-a-string-function-result-in-a-concat-leaks-on-every-cross-target` | the four cross backends, at CONCAT | a heap measurement |
| `bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64` | x86-64, at COMPARISON | a heap measurement from a *sixth* backend being written |

Two bugs, opposite halves, both silent, both caught only because somebody
measured a heap figure and it disagreed with an oracle. **No test caught either,
and no test would catch the next one.** The second was found only because the
wasm32 lane built the same lowering and could not reproduce native's number —
i.e. the detector was a new backend, which is not a repeatable strategy.

The first ticket's own write-up (still in the comment at `ir_codegen.inc:6096`)
called itself *"the FIFTH hand-written copy of that predicate"* and fixed the
copies. Fixing copies does not remove the need for copies, which is why the
other half stayed broken.

## Census at HEAD (`aa78a7faf63a`)

`bug-a-...-comparison-leaks-on-x86-64` reduced x86-64's three comparison sites to
one shared predicate (`IRStrCmpOwnsOperand` / `IRStrCmpNeedsRelease` /
`IREmitStrCmpSaveOperands` / `IREmitStrCmpReleaseOperands`, `ir_codegen.inc:4763-4789`).
It deliberately stopped at its own file. The rest stands:

| backend | `IRNodeOwnsManagedStr` call sites | routed via a shared helper |
| --- | ---: | --- |
| `ir_codegen.inc` (x86-64) | 9 | yes — 5 of them |
| `ir_codegen386.inc` | 6 | no |
| `ir_codegen_arm32.inc` | 6 | no |
| `ir_codegen_aarch64.inc` | 7 | no |
| `ir_codegen_riscv32.inc` | 6 | no |
| `ir_codegen_wasm32.inc` | 3 | no |

Reproduce with `grep -c IRNodeOwnsManagedStr compiler/ir_codegen*.inc`.

Per `devdocs/dev/root-cause-over-microfix.md`: two mechanisms for one concept is
a smell, three is a design flaw. This is five files and ~25 sites for one
question.

## Two candidate shapes, and they are not equivalent

1. **A shared `IRReleaseOwnedStrOperands(left, right)` hook** each backend calls
   once per string-operand-consuming site. Removes the copies but not the
   requirement to *call* it — a new site that calls nothing still leaks silently.
   Strictly better than today; not a guarantee.
2. **An oracle** asserting every site of the three kinds (concat, equality,
   ordered) is paired with a release, in the shape of the `abi.inc` oracle.

**Do not reach for shape 2 without reading
`bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire` first.**
That is an open ticket saying the very oracle being held up as the template is
enforced by a grep that cannot fire. Copying its shape without reading it would
reproduce a guard that has never been able to fail — the same family as
`feature-t-audit-tests-that-pass-with-the-implementation-removed`. If shape 2 is
chosen, the guard must be shown to fail on a deliberately broken tree before it
is trusted, and that demonstration belongs in the commit message.

The honest recommendation is **1 plus a demonstrated 2**, in that order, and 1
alone is worth doing if 2 stalls.

## Why p45 and not higher

Both known instances are fixed; this is the mechanism that produced them, not a
live defect. Nothing leaks today that we know of. It earns its place because the
cost of the next instance is another silent unbounded leak in a common idiom
found by luck — but it is not urgent, and it should not preempt a live red.

## Scope and ownership

Touches `ir_codegen386.inc`, `ir_codegen_arm32.inc`, `ir_codegen_aarch64.inc`,
`ir_codegen_riscv32.inc` (and `ir_codegen_wasm32.inc` if that lane wants in) —
i.e. **four to five backend files at once**, which is why it wants a session that
holds them all and is not racing another Track A agent. Gate is
`make compiler/pascal26` + the cross targets touched; the heap repro from
`bug-a-...-comparison-leaks-on-x86-64` is the regression probe and should be run
per target, not just natively.

## Verification the fix would need

The two closed tickets each carry a repro program that reads a flat heap figure
when correct. A refactor here must leave **both** flat, on **every** backend —
which is the test neither bug had, and arguably the most valuable thing this
ticket could leave behind even if the unification itself is deferred.
