---
track: A
prio: 66
type: refactor
blocked-by: []
summary: "Four dispatchers and TWO independent defaults mechanisms serve one concept. Put the PySig record on the boundfn carrier and DELETE pyboundfn_setdefaults, so every callable shape answers signature questions from one place. Filed as work because it was banked as a note at the bottom of a resolved ticket, where ready/next cannot see it."
---

# One signature record for every callable carrier

> **RESHAPED 2026-08-19, after frank2 landed steps 1 and 2 (`9e711a681`). This ticket is
> now step 3 alone, it got materially CHEAPER, and it gained a second motivation.**
>
> **Cheaper:** the PYSIG record already carries code, `ReqN`, `TotN`, `Star`, `Dflts` and now
> `Names` (`PYSIG_SIZE` 40 -> 48). Putting `Sig` on the boundfn carrier and deleting
> `pyboundfn_setdefaults` is therefore a **port onto an existing structure, not a design**.
> The ordering argument in this ticket held: step 3 was correctly refused first, because the
> record was still missing the field the carriers would need.
>
> **The new motivation, which is the more important half.** frank2 gave a carrier with no
> names a **named refusal** rather than a wrong answer — today only the tag-8 pair has a
> signature. That was the right call (a silently dropped keyword would bind the default and
> return something plausible), but it means there is now a *reachable diagnostic* standing in
> for a feature. **Completing this ticket turns that refusal into a correct answer for every
> callable shape.** So it is no longer only a tidy-up that deletes a mechanism; it closes a
> user-visible gap. Re-rank accordingly when the queue reaches it.
>
> Two design decisions from `9e711a681` that constrain how the port must behave, both worth
> preserving rather than rediscovering: keywords bind to positions **first**, then remaining
> holes fill from defaults (that order is the only reason writing a keyword beats a default);
> and the missing-required-argument count is recomputed **after** keyword binding rather than
> trusting the positional count, because a keyword can supply a required parameter
> (`r(a=1, b=2)`).

**Filed 2026-08-19 by the coordinator at frank2's request, who banked the finding while
resolving p88 and then confirmed on measurement that it wants its own sitting.**

## Why this is a ticket and not a note

It was already written down — at the bottom of
[[feature-n-a-callable-value-carries-its-signature-type]], resolved, in `done/`. A
conclusion parked in a closed ticket is invisible to `ready`/`next`, so it gets
rediscovered rather than done. That is the same failure this repo has recorded repeatedly;
the fix is a queue entry with a `track:` and a `prio:`, which is the only thing the ranker
reads.

## The finding, in frank2's words

> **Count the mechanisms before extending this.** There are now four dispatchers for one
> concept — `pybound_callv*`, `pycallback_call*`, `PyCallKey1`, `pyvar_callv*` — and two
> independent defaults mechanisms. The signature record this ticket built is the general
> one; the honest next step is to put `Sig` on the boundfn carrier too and DELETE
> `pyboundfn_setdefaults`, rather than teach a fifth path the same trick.

Four mechanisms for one concept is past the threshold this repo already names: two is a
smell, three is a design flaw. The second defaults mechanism (`pyboundfn_setdefaults`)
fires for the **nested** def form and not the module-level one, which is exactly the kind
of split that produces a bug on one arm and a working sibling on the other.

## Why it is Track A, despite being NilPy-facing

It touches `compiler/ir.inc` and `compiler/builtin/pyeval.pas` — shared internals and a
builtin RTL source. Two consequences:

- Gate is Track A's: `make compiler/pascal26` (the fixedpoint) + `tools/gate.sh quick`.
- **A `compiler/builtin/**` change needs `make stabilize-fast && make pin` before the
  fixedpoint gate reflects it.** Landing it without the pin leaves the frozen builtin
  sources and the compiler disagreeing.

## Why it is blocked, and the ordering is not negotiable

Do **not** start before
[[bug-n-a-keyword-argument-through-a-callable-value-is-undefined]] lands. frank2's measured
recommendation:

1. extend PySig with parameter **names**,
2. lower a keyword argument at a callable-value call site into a name/value pair the
   dispatcher can match,
3. **then** put `Sig` on the boundfn carrier and delete `pyboundfn_setdefaults`.

Steps 1 and 2 are the blocking ticket. Step 3 is this one, and it gets **cheaper** after
them, because by that point the record is the obvious single source for every signature
question and the deletion is subtraction rather than a migration. Attempting the
consolidation first means migrating carriers to a record that is still missing the field
they will need.

## Gate

Track A's: fixedpoint + `gate.sh quick`, then `stabilize-fast` + `pin` for the builtin
change. Success is measured in **mechanisms deleted**, not lines: `pyboundfn_setdefaults`
gone, and the nested and module-level def forms answering defaults from the same place.

## Log
- 2026-08-19 — filed. Blocked on the keyword-names work by design.
