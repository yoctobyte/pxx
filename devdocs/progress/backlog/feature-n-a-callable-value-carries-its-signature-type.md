---
track: A
prio: 88
type: feature
owner: unassigned
blocked-by: []
summary: "DECIDED 2026-08-19. A boxed callable's VT_CALLABLE_TAG payload becomes ONE pointer to a static signature record {code address, ReqN, TotN, per-param default descriptor}. Static, so the slot still owns nothing and no refcount behaviour changes. One call-site helper reads it: check arity, fill defaults, call. Unblocks three tickets whose symptoms are SIGSEGV and silent wrong values."
---

# A callable value carries its signature type

**Implements [[decide-how-a-compiled-def-carries-its-signature-when-boxed]] (decided by
the user, 2026-08-19).** Filed as work because a decided ticket that is never re-filed is
invisible to `ready`/`next` and gets rediscovered later, sometimes with a fix the decision
already rejected.

**Track A, not N:** it changes the variant payload contract in `defs.inc` and the call
lowering — shared compiler internals. Whoever holds A owns it.

## What to build

`VT_CALLABLE_TAG`'s payload becomes **one pointer to a static signature record**:

```
{ code address; ReqN; TotN; per-parameter default descriptor[] }
```

- **One payload word only.** A variant is 16 bytes: 8-byte tag + 8-byte payload. So the
  code address lives *inside* the record; there is no room for address + ID side by side.
- **The record is static** — emitted at compile time, never allocated, never freed. The
  slot therefore still owns nothing, and the deliberate non-owning lifetime recorded in
  `defs.inc` ("that is the lifetime these values already had while they wore VT_INT64")
  is preserved **by construction**. **No retain/release change anywhere.** This is the
  property the decision turns on — do not trade it away for convenience.
- **Per-parameter default descriptor** holds *either* the constant-folded value *or* the
  address of the hidden global that `ProcParamDefaultSym` already maintains for a
  non-constant default. Python evaluates defaults once at `def` time, and that mechanism
  already exists — **do not rebuild the value at the call site**, or the shared-mutable-
  default idiom (`def f(a=[])`) stops being observable.
- **One call-site helper, written once:** read `ReqN`/`TotN`, check the actual argument
  count, fill missing defaults from the record, call the code address.

## Do this too, or the win is half-taken

Give `TPyClosure` **the same signature type**. Then the two callable shapes differ only in
**ownership**, never in what a signature *is*, and the helper is written once against the
type rather than once per shape. That is what recovers the goal of the rejected
"route everything through the owned path" option without touching lifetimes.

## Context that prevents two wrong turns

- **`VT_CALLABLE_TAG` already carries two payload kinds** — "usually a static code
  address; it may also be a BORROWED heap callable" — and run-time dispatch already tells
  callable shapes apart by the object's magic, never by this tag. So this adds a payload
  kind to a tag that has them; it is not a third convention.
- **Do not "resolve the target statically where possible" and diagnose the rest.** That
  was explicitly considered and rejected: it fixes the one row that does not crash and
  leaves every row that does — dispatch table, handler list, callback parameter, bound
  method — still segfaulting. A passing test certifying a hole.

## What it unblocks

- [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]] (currently
  `unfinished/`) — the measured evidence lives there.
- [[bug-n-a-call-through-a-callable-value-drops-the-callees-defaults]]
- [[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]] (`blocked/`)

Symptoms today: `handlers[0](1)`, `d["x"](1)`, `def call(fn): fn(1)` and a bound method
`cb = k.m` all **SIGSEGV**; `zz(1,2,3)` against a 2-parameter def returns a **wrong value
with exit 0**.

## Accepted limitation

Signatures are fixed at compile time; a callable synthesized at run time the way CPython
can is not covered. Not a new constraint — NilPy is a compiler, and the `pyeval` library
is where genuinely dynamic Python is expected to be served.

## Gate

Track A: `make compiler/pascal26` (the byte-identical self-host fixedpoint) + repro +
`tools/gate.sh quick`. Land green.
