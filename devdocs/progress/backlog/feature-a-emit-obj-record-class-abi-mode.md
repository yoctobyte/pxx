---
track: A
prio: 40
type: feature
blocked-by: []
summary: "--emit-obj objects built with and without --compact-classes disagree on VMT slot numbers, and nothing diagnoses it. Record the class-ABI mode in the object and refuse a mismatched link, the way --threadsafe's hazard is meant to be handled."
status: backlog
---

# `--emit-obj` should record the class-ABI mode

Raised by [[feature-a-tobject-root-method-vmt-slots]], which made
`--compact-classes` an ABI-splitting switch.

## The hazard

`--compact-classes` sets the reserved root VMT slot count to 0; without it, 4.
Every class's own virtuals therefore start at a different index. Two `.o` files
built with different settings, linked together, disagree on what slot `k` means:
a call through a base reference lands on the WRONG METHOD — no diagnostic, no
crash at the call, just a plausible wrong result. Exactly the failure class
CLAUDE.md's debugging note is about.

`--platform=esp` implies compact, so the mismatch is reachable without anyone
typing the flag.

## What to build

Record the mode in the emitted object (a note section / a symbol whose name
encodes it — whichever costs less in `elfwriter.inc`), and refuse the link when
two inputs disagree, naming both files and the flag. `--threadsafe` carries the
same class of hazard and deserves the same treatment; do them together if the
mechanism generalises.

## Gate

`make compiler/pascal26`, `tools/gate.sh quick`, plus a test that links a compact
object against a default one and asserts the REFUSAL (not a wrong answer).
