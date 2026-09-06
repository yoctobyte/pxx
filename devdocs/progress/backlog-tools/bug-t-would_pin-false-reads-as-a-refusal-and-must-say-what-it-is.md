---
slug: bug-t-would_pin-false-reads-as-a-refusal-and-must-say-what-it-is
title: "`would_pin: false` reads as a refusal; make the shadow verdict say it is advisory"
track: T
type: bug
prio: 55
status: backlog
owner: ""
created: 2026-09-06
found-by: owner (ruling); recommendation 2 of decide-what-a-pin-means-and-what-may-block-one
blocked-by: []
summary: "ROUTED BY THE OWNER 2026-09-06, recommendation 2 of the p80 pin decision. `pin_shadow()` publishes `would_pin: false` and it has ZERO authorised consumers -- the function's own docstring says it 'deliberately never touches pinned, make pin, or stable_linux_amd64/**'. It is read as a refusal anyway: THREE sessions reasoned carefully from it and all three read permission where none was expressed, and the fleet cut no pin for 49 hours. The fix is the wording, not the reader -- CLAUDE.md says so about this exact field. Make the output state what it is and what it is not, e.g. 'advisory -- 12 reds this pin does not have; pinning is NOT blocked'. THE TEST FOR ANY REPLACEMENT: a session reading only that line, with no CLAUDE.md in context, must not be able to construe it as authority. A boolean named `would_pin` cannot pass that test whatever its docstring says, so renaming the FIELD is in scope, not only its rendering."
---

# Make the shadow verdict say what it is

## Why this is a wording bug and not a reader problem

`pin_shadow()` is advisory by construction and says so in its own docstring.
`would_pin` has **no readers** — one assignment, one comment. `pin_is_green` is
used once, to name a rollback target, and the owner has since ruled that **this
fleet does not roll back**.

**Three sessions read `would_pin: false` as a refusal**, independently and
carefully, and the fleet went 49 hours without a pin. CLAUDE.md's own conclusion
on the incident: *"a verdict nobody may act on gets read as authority anyway, so
the fix is the wording, not the reader."*

## What it must say

State the fact and the non-implication together. Something in the shape of:

```
advisory — 12 reds this pin does not have; pinning is NOT blocked
```

**The test for any replacement: a session reading only that line, with no
CLAUDE.md in context, must not be able to construe it as authority.** A boolean
called `would_pin` cannot pass that test whatever its docstring says — the name
carries a verdict — so **renaming the field is in scope**, not just re-rendering
it.

## What must NOT change

`pin_shadow()` must keep never touching `pinned`, `make pin`, or
`stable_linux_amd64/**`. This ticket makes an advisory line legible; it does not
give it teeth.

## Context, decided the same day

The owner ruled that pins happen on a regular cadence **green or not**, and that
the only thing that gates one is the self-host fixedpoint row. A fleet pinning
on a cadence with reds will read `would_pin: false` **more** often, not less —
which is what moves this from a tidy-up to the highest-value item on that
ticket.
