---
slug: bug-n-async-def-and-await-are-not-implemented
track: N
prio: 60
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "`async def` is refused -- `undefined variable (async)`, so the keyword is not in the grammar at all. Python 3.5. Distinct from yield-from in that a correct implementation needs an event loop and not just a parser arm, so the honest first step may be deciding how far to go rather than typing. Found by the same probe suite as the sys.version_info ruling."
---

# N: `async def` / `await` are not implemented

## Repro

```python
async def go():
    return 1
print("ok")
```

```
pascal26:1: error: undefined variable (async)
```

`async` is being read as an identifier, so the keyword is absent from the
grammar entirely — the failure is at the first token of the declaration, before
anything about coroutines is reached.

## Why this is a bug and not a divergence

Same charter clause as its sibling: *if code works on CPython, it must work on
NilPy*. `async def` is Python **3.5** and is ordinary code in a large fraction
of modern libraries.

## Why it is filed separately from `yield from`, and lower

[[bug-n-yield-from-is-not-implemented]] is a missing form over machinery that
exists — NilPy has generators. This one is not: `async`/`await` need a coroutine
object, an awaitable protocol and **an event loop** to drive them, and the
libraries that use `async def` reach for `asyncio` in the next line. A parser arm
that accepts the syntax and produces something that cannot be awaited would be
worse than the current clean refusal.

So the honest first step is probably **a decision, not an implementation**: how
far into async does NilPy go — the syntax with a minimal driver, an `asyncio`
subset, or nothing and a documented divergence? If the answer is "nothing", this
becomes a `rejected/` ticket citing the divergences doc, and that is a legitimate
outcome. **Whoever picks this up should expect to file `decide-how-far-nilpy-
goes-into-async` before writing code**, rather than to start with the parser.

Filed at 60 rather than its sibling's 65 for exactly that reason: the size is
unknown and the first move is not typing.

## How it was found

The same nine-probe suite that produced
[[decide-nilpy-what-version-does-sys-version-info-claim]] (owner, 2026-08-30) —
written to price a version claim, not to audit the language. Two of the nine
failed far below the expected level; this is the second.

## Relationship to the version claim

[[feature-n-sys-version-info-implementation-and-the-probe-suite]] pins this as
refused, as a tripwire on the 3.9 claim rather than an endorsement of the gap.

## Gate

If it is implemented: `make test-nilpy` green + self-host byte-identical +
cross, plus a program that actually awaits something and observes the result —
not merely one that parses. If it is rejected, no gate: the divergences doc
entry is the deliverable.
