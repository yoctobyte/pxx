---
track: U
prio: 88
type: decision
blocked-by: []
summary: "A compiled NilPy `def` boxed into a variant is a bare CODE ADDRESS (VT_CALLABLE_TAG), carrying no arity and no defaults — so every call through a procedural value skips default-filling AND arity checking, and the ordinary callback shapes SIGSEGV. A lambda is correct because it takes the owned-callable path, which already carries ReqN..TotN. Fixing it means changing what a def-as-value OWNS, which the current representation deliberately avoids. That ownership call is the decision."
status: backlog
owner: unassigned
---

# How should a compiled `def` carry its signature when boxed as a value?

- **Type:** decision — **Track U**
- **Raised:** 2026-08-18 by frank2-7e, from
  [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]]
  (N, p88), where the full measured evidence lives.
- **Escalated rather than guessed:** the fix is a lifetime change and the
  narrow alternative is a known trap. Both are spelled out below.

## The fork

A compiled `def` reaching a variant is boxed as **VT_CALLABLE_TAG (12) — a bare
code address**. An address has no arity and no defaults, so a call through it
fills no defaults and checks no arity: `handlers[0](1)`, `d["x"](1)`,
`def call(fn): fn(1)` and a bound method `cb = k.m` all **SIGSEGV**, and
`zz(1,2,3)` against a 2-parameter def returns a wrong value with exit 0.

A **lambda is correct**, because it takes the owned-callable path
(`pyvar_of_callable` → VT_PYCLOSURE/VT_BOUNDFN) and `TPyClosure` already carries
`ReqN..TotN`. So the repo has **two representations for one concept**, and only
one of them knows its own signature.

## Options

**A. Route compiled defs through the owned-callable representation** (what
lambdas do). Deletes the second mechanism rather than extending it; the
machinery already exists and is proven.
*Cost:* the slot would then OWN the callable. `defs.inc` chose the bare address
deliberately — *"the slot does NOT own it… that is the lifetime these values
already had while they wore VT_INT64"* — so this changes retain/release for every
def-as-value. Getting it wrong is a leak or a double-free, both silent.

**B. Give VT_CALLABLE_TAG a payload that carries the signature** (a static
descriptor beside the code address: arity range + default values). Keeps the
non-owning lifetime exactly as it is, since a static descriptor is not heap.
*Cost:* a second callable shape to keep in step with the closure one — i.e. it
preserves the two-mechanism smell instead of removing it.

**C. Resolve the target statically where possible** (`zz = loc`) and diagnose the
rest.
*Not recommended, recorded so it is not re-proposed:* it fixes the one row that
does not crash and leaves every row that DOES — dispatch table, handler list,
callback parameter, bound method — still segfaulting. A passing test certifying
a hole; the same trap the `CodecInfo` probe caught earlier the same day.

## Recommendation

**B if the ownership change in A cannot be made confidently; A if it can.** The
decision is genuinely about ownership, not about design taste: A is the
normalising answer and would delete a case, but it edits refcount behaviour for a
value class that currently has none, and this repo's expensive bugs are the silent
ones. B is strictly additive and safe, at the price of keeping two shapes.

Either way the *call site* should stop guessing: the value should carry its
signature. What must NOT happen is teaching the call site to infer it.

## Why it needs a human

The trade-off is "delete a mechanism but touch lifetimes" versus "keep two
mechanisms but touch nothing else". That is a project-direction call, and
`devdocs/dev/normalise-dont-special-case.md` argues for A while the comment in
`defs.inc` argues the lifetime is load-bearing. Both are repo doctrine and they
point opposite ways here.

## Scope reduced 2026-08-18: this gates TWO items, not three

`feature-nilpy-yield-outside-a-for-loop` was listed as waiting on this decision, on the
reasoning that a generator's iteration protocol "may want a callable to carry state."
**Measured, and it does not.** Verified by the coordinator at HEAD:

- The engine **refuses generator METHODS outright** —
  `parser.inc:31543: 'stackless generator/async methods are not supported (v1)'`. So the
  boxed-callable route was never available to that ticket in the first place.
- The route that DOES work needs no callable value at all: a lifted free function taking
  the receiver, consumed by a plain for-in. Confirmed on the exact html5lib nested-filter
  shape — a generator iterating a generator, with `continue` — which prints `10 20 40 50`.

So yield is **not blocked on this decision** and the "read the ruling first" note has been
struck from that ticket.

**Still gated (both on measured evidence, not bookkeeping):**

1. `bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module` (p85) —
   static rebinding; re-measured at HEAD, still 18 where CPython says 5, reproduces with
   no import at all.
2. `bug-n-a-call-through-a-callable-value-drops-the-callees-defaults` (p70) — a boxed def
   carries a code address and no signature, which IS this decision's subject.

The second was confirmed independently from the other side by the worker that hit the
same wall while fixing the rename cluster, rather than inherited from this ticket.

---

# DECIDED 2026-08-19 by the user — **Option D: the signature becomes a TYPE**

Neither A nor B as written. The user's framing, which is better than both and is what
gets built:

> "We know the type information. We just could make that function definition a **type**,
> and store the type ID alongside the pointer. The caller may need some (one-time
> written) helper to call that type."

## The design

The `VT_CALLABLE_TAG` payload becomes **one pointer to a static signature record**:

```
{ code address, ReqN, TotN, per-parameter default descriptor[] }
```

**A variant is 16 bytes — 8-byte tag + 8-byte payload — so there is exactly ONE payload
word.** That is why the code address moves *inside* the record rather than sitting beside
a type ID: "type ID alongside the pointer" collapses into "the payload IS the signature,
and the code address lives in it."

**The record is emitted at compile time and never allocated, so the slot still owns
nothing.** The lifetime property `defs.inc` protects deliberately — *"the slot does NOT
own it… that is the lifetime these values already had while they wore VT_INT64"* — is
preserved **by construction**, not by care. That is the whole reason this beats Option A:
no retain/release change for a value class that currently has none, so neither of A's
silent failure modes (leak, double-free) is reachable.

The call site gets **one helper, written once**, against the signature type: read
`ReqN`/`TotN`, check the actual argument count, fill missing defaults from the record,
call the code address.

## Two findings that made the decision safe, both from reading rather than assuming

**1. The "second shape" objection was already overstated.** `VT_CALLABLE_TAG`'s own
comment says the payload is *"USUALLY a static code address; it may also be a BORROWED
heap callable"*, and that *"run-time dispatch never keys on this tag — `PyCallableObj`
tells the shapes apart by the object's magic."* So the tag **already** carries two payload
kinds and a discrimination mechanism **already** exists. This adds a payload kind to a
tag that has them; it does not invent a third convention.

**2. Non-constant defaults are ALREADY solved, which was the one real risk.** Python
evaluates defaults once at `def` time, so a default need not be a compile-time constant
(`def f(a=[])` — the shared-mutable-default idiom is observable). A purely static record
could not hold such a value. But `ProcParamDefaultSym` already exists: *"symbol of the
hidden global holding a NON-CONSTANT default's def-time value… the call site therefore
reads this global rather than rebuilding a value."*

So each per-parameter descriptor holds **either** the constant-folded value **or** the
address of that hidden global. Both are compile-time known and static. **The hard case was
built before this decision was taken.**

## The synthesis that recovers most of what Option A wanted

Because the signature is a real interned **type**, `TPyClosure` can carry **the same
signature type**. The two callable shapes then disagree only about **ownership**, never
about *what a signature is*, and the call-site helper is written once against the type
rather than once per shape. Option A's actual goal — one notion of a signature, one call
path — is obtained without touching lifetimes.

## Accepted limitation, stated so it is not later read as a regression

Signatures are fixed at compile time, so a callable synthesized at run time the way
CPython can (dynamic module load, runtime class synthesis) is not covered. **This is not
a new constraint** — NilPy is a compiler, not an interpreter, and already accepts it
everywhere. The user's note on the escape hatch: the **eval library** (`pyeval`) is where
genuinely dynamic Python is expected to be served, partly or wholly.

## Re-filed as work (a decided ticket that is never re-filed is invisible)

See `feature-n-a-callable-value-carries-its-signature-type`. Do **not** leave this in
`decided/` as the only record — `ready`/`next` do not read decisions.
