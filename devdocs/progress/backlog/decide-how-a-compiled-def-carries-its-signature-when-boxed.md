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
