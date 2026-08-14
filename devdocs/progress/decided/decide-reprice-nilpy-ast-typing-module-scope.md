---
track: U
prio: 55
type: decide
blocked-by: []
summary: "feature-n-nilpy-ast-typing-module-scope sits at prio 55 — top of the ranked Track N queue after the META — but its own 2026-08-09 note concludes it is now an OPTIMISATION, not a correctness item, and asks to be re-priced. prio is the user's field, so: re-price, or leave it steering the queue?"
status: decided
---

# Re-price `feature-n-nilpy-ast-typing-module-scope`?

- **Track U** — a one-field decision, no code. Filed rather than acted on
  because `prio:` is the human's steering signal and an agent quietly lowering
  it is exactly the kind of silent re-prioritisation the ranker exists to
  prevent.

## The fork

`feature-n-nilpy-ast-typing-module-scope` carries `prio: 55`, which makes it the
top ranked **actionable** Track N item (above it is only the META ticket
`feature-nilpy-thirdparty-libraries-as-targets`, whose work lands as children).
So every agent running `tools/progress.sh next --track N` is pointed at it.

Its own closing section, written 2026-08-09 after the last round of work, says
otherwise:

> An unreadable shape no longer costs a wrong value; it costs a `tyVariant` slot
> where a narrower one would have done. That is a performance cost, not a
> correctness one, so **this ticket should now be read as an OPTIMISATION item
> rather than a correctness one — and re-priced accordingly.**

The re-pricing it asks for was never applied.

## What remains in it, for calibration

The route the ticket names as its real close is: make the module pre-pass able
to trial-parse an as-yet-unseen name without `Error()` **halting the compiler**
— `Error` calls `Halt` directly today. That is a Track A change to the
compiler's error machinery with a wide blast radius, in service of a
`tyVariant`-instead-of-narrower slot.

Everything that was a *correctness* defect in this ticket has shipped: item (2)
(`x = c.two(1)`), and the block-nested binding widening (with the `tkFloat`
gap that was hiding half of it).

## Options

1. **Re-price to ~25-30** (what the ticket asks for). It stops steering the
   queue; the real correctness work in Track N ranks above it again. The
   `Error`-does-not-Halt refactor gets picked up when someone wants it for its
   own sake — and it likely has better justifications than this ticket.
2. **Leave at 55.** Defensible if the `Error`/`Halt` refactor is wanted soon for
   *other* reasons (it would unblock several "trial-parse this and recover"
   ideas), and this ticket is the convenient carrier for it.
3. **Split**: drop this ticket to ~25 and file the `Error`-must-not-Halt
   refactor as its own Track A ticket at whatever priority that capability
   deserves. Probably the honest shape — the two things are not the same size
   and are wanted for different reasons.

**Recommendation: option 3.** The capability and the optimisation are being
ranked as one item, and it is the capability that carries the value.

## DECIDED 2026-08-14 by the user — prio 8

> *"Eight. It makes no sense to optimize a halt()."*

Lower than the ticket's own suggested 25-30, and for a better reason than
"optimisation ranks below correctness". The work **cannot be done as written**:
the inference needs a pre-pass that trial-parses an unseen name, and `Error()`
calls `Halt` directly, so a speculative parse cannot back out. An optimisation
gated behind a fatal path is not a low-priority item, it is a blocked one.

`feature-n-nilpy-ast-typing-module-scope` re-priced 55 -> 8, so it stops being
the top actionable Track N item. The real work is filed as
[[feature-a-error-does-not-halt-so-a-parse-can-be-speculative]] — which ranks on
its own merits, and has better justifications than type inference:
multiple-error reporting, better diagnostics, and any other speculative parse.

## Log
- 2026-08-14 — decided, commit c7d65da83.
