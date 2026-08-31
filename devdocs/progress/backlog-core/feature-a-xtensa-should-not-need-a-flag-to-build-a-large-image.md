---
slug: feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image
track: A+S
prio: 35
type: feature
status: new
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "--xtensa-long-calls builds a large image today (bug-a-xtensa-cannot-widen-a-forward-call-..., closed) but the user has to know it exists, and a program that needs it fails with an error until they do. The right default is to widen only the forward calls that need it. The per-body relaxation that closed the forward JUMP wall does NOT transfer -- a jump's fixups are per-body and a call's are whole-program, so the analogous retry is a second parse. A veneer pool is the untried candidate and is more attractive here than it was for jumps: CALL0 reaches +-512 KiB against J's +-128 KiB, so a trampoline at the END OF THE CALLING BODY is within the call site's reach, where the jump case's veneer was not."
---

# xtensa should not need a flag to build a large image

- **Filed:** 2026-08-31 by frankA, on closing
  [[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]]
  with the flag rather than with the fix.
- **Nothing is broken.** The flag works and the error names it. This is about
  the default.

## Why it is only prio 35

Every xtensa program that is not the compiler itself fits inside CALL0's range,
so the population that needs this is one program, and that program has an
answer. Ranked below anything a user actually hits.

## The two candidates, and what each owes

**A veneer pool.** At `ApplyCallFixups`, an out-of-range forward call is
redirected to a trampoline that does the long-form jump. The trampoline has to
be within CALL0's ±512 KiB of the CALL SITE, which rules out the image tail and
points at *the end of the calling body* — reachable, since no single body is
512 KiB. What it owes: somewhere to put it. The body is already emitted and
everything after it has been placed, so this still needs either reserved space
per body (a cost paid by everyone, which is what the flag already is) or a
layout pass that can insert.

**Two-pass compilation.** Compile, collect the set of call sites that did not
reach, compile again with exactly those widened. Correct and minimal in output
size; costs a second parse, and needs the driver to be re-entrant, which is the
part nobody has checked.

## Do not reach for the jump fix

`IREmitMachineCodeXtensa` relaxes by re-emitting ONE BODY, which is bounded and
whose restorable state is enumerated in a comment there. Calls are patched
whole-program. The shape looks identical and is not — see the closed ticket.
