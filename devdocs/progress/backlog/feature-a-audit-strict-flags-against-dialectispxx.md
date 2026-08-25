---
track: A
prio: 12
type: feature
summary: "`DialectIsPxx` now exists and only `--strict-overload` consults it. The other six strict flags apply everywhere, including to our own {$MODE PXX} RTL. Audit each one: does it WANT the ownership carve-out, or is it right to judge every file?"
status: backlog
---

# Audit the remaining strict flags against `DialectIsPxx`

Follow-on from
[[feature-a-strict-flags-scope-to-dialect-ownership-not-program-vs-unit]], which
established the predicate and rescoped exactly one flag.

## State after that ticket

`DialectIsPxx` (`compiler/symtab.inc`) answers "is the code being compiled right
now written in the pxx dialect", driven by `{$MODE PXX}` and already declared by
144 library files. **One** check consults it — the `StrictOverload` test in
`compiler/pasparser_proc.inc`.

The other flags in `EnableStrictFpc` — `StrictOperator`, `StrictCase`,
`StrictVisibility`, `RequireForward`, `StrictShiftWidth`, `StrictVariantChar` —
never tested `CurrentUnitIdx`, so there was no wrong axis to fix and nothing was
changed. They judge every file, our RTL included.

## The question, per flag

That is not automatically wrong, and this ticket is **not** "add
`DialectIsPxx` to all of them". The flags split into two kinds and the split is
the whole job:

- **Rule-shaped** (`StrictOverload`, `RequireForward`, `StrictCase`,
  `StrictVisibility`): "code must be WRITTEN this way". Applying these to our
  RTL means a command-line flag re-judging library source that is already
  written and shipped — the exact thing the parent ticket argued against. These
  are the candidates.
- **Semantics-shaped** (`StrictShiftWidth`, `StrictVariantChar`, and parts of
  `StrictOperator`): "this expression EVALUATES to a different value". Exempting
  the RTL here would be actively harmful — it would give one program two numeric
  behaviours depending on which side of a unit boundary the expression sits,
  which is worse than either answer alone. These almost certainly should stay
  global, and saying so explicitly in the code is the deliverable for them.

So: for each flag, decide which kind it is, and either wire `DialectIsPxx` in or
write the one-line comment explaining why it is deliberately global. A flag that
turns out to be BOTH (a rule whose violation also changes evaluation) is the
interesting case — escalate it as a Track U `decide-*` rather than guessing.

## Why prio 20

Nothing is broken today: these flags are opt-in, off by default, and our RTL
compiles under them (that is what `--strict-fpc`'s corpus claim rests on). This
is consistency work on an experimental surface, worth doing before a second flag
grows its own copy of the ownership condition — which is the failure mode
`NilPyUserCode`'s nine copies already demonstrated in this codebase.

## Gate

Each flag either consults `DialectIsPxx` with a test proving the carve-out, or
carries a comment saying why it does not. `--strict-fpc` still compiles the RTL
and the conformance pass-set.
