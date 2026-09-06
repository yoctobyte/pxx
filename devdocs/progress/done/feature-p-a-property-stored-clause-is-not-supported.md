---
slug: feature-p-a-property-stored-clause-is-not-supported
title: "A property's `stored` clause is refused, on ordinary published properties FPC accepts"
track: P
prio: 45
type: feature
blocked-by: []
status: done
owner: frankB
created: 2026-09-06
summary: "`published property F: Integer read FF write FF stored False;` is refused with `expected ':' before 'False'`. FPC accepts it, and `stored` is a STREAMING attribute -- it decides whether a property is written out -- so the consumer is `lib/pcl`, our own widget set, and any .lfm round-trip. Measured 2026-09-06 by probe while dispositioning tclass14a, whose `%FAIL` was being satisfied by this gap rather than by its own subject (that `stored` is invalid on a CLASS property specifically)."
---

# The measurement

```pascal
program p; {$mode delphi}
type TC = class
     private FF: Integer;
     published property F: Integer read FF write FF stored False;
     end;
begin end.
```

```
pascal26: error: expected ':' before 'False'
```

FPC accepts this. The clause also takes a field or a parameterless boolean
method (`stored FIsStored`, `stored GetStored`), not only a constant.

# Why it is ranked here rather than lower

`stored` is not decoration: it is what a streaming system asks before writing a
property out, so it is load-bearing for anything that persists a component. We
ship `lib/pcl` and `test_pcl_lfm` reads an `.lfm`. A form that round-trips
through us today cannot express "do not persist this property".

# How it was found, which is the part worth keeping

Dispositioning `tclass14a`, a `%FAIL` row whose own comment says *"class
properties are not for sreaming therefore 'stored' is not supported"*. pxx
refuses the row, so it counted as a pass — **for the wrong reason**. The
discriminator was probing the construct where it is LEGAL: an ordinary published
property. That is refused too, so the row was never testing its own subject.

`task-t-twelve-syntax-shaped-fail-rows-may-be-refused-by-a-parse-gap-rather-than-their-own-subject`

## Resolution

Landed with
[[bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker]]
in one commit, because they are the same arm: `stored`, `default <value>`,
`default;`, `nodefault` and the hint directives are now one
`ParsePropertyTailDirectives` in `compiler/pasparser_decl.inc`, called from both
the ordinary and the REDECLARATION branch of `ParsePropertyDecl` — which had
written the `default` arm and the hint loop out twice and carried the same bug
in both copies. Splitting `default` into its two clauses without also taking
`stored` would have left a second procedure to write.

`stored` takes ONE operand — a constant, a field name, or a parameterless
boolean method name — parsed and DISCARDED. pxx has no RTTI streaming, so it has
no consumer today; what was load-bearing was that its presence made the whole
declaration unparseable. `stored` with no operand (`stored;`) is refused with
`"stored" needs a constant, a field name or a parameterless boolean method`
rather than silently accepted, so the clause cannot become a no-op by accident.

Rows E..H of `test/test_a_property_default_clause_is_two_clauses.pas` cover
`stored False`, `stored <method>`, and `stored` and `default` on one property,
against `fpc -Mdelphi` 3.2.2's own output.

### One row of the ORIGINAL probe was dropped rather than fixed

`stored FF` — an Integer FIELD — is accepted by pxx and refused by fpc (*"The
type of the storage symbol must be boolean"*). Us accepting what fpc rejects is
not a defect, so the row came out of the test rather than the compiler growing a
type check for a value it discards.

### The residual, and it has an owner

`stored` now parses on a CLASS property, where fpc refuses it. That is the same
"we accept what fpc rejects" rule and would normally end here — except frankS
found the sibling that makes it an INTERNAL inconsistency rather than an
FPC-parity question: `tclass14b` is a published class property, and pxx already
refuses that with `a class property cannot be published`
(`pasparser_decl.inc:6735`). `published` and `stored` are two spellings of one
rule — a class property has no instance, so nothing about streaming applies to
it — and we implement it for one spelling only. Narrowing follows in its own
commit, worded to match the existing arm, because a refusal's risk is refusing
working code and it gets its own gate.

### It retires a false pass, and that is worth more than the feature

`tclass14a` is an fpc-testsuite `%FAIL` row whose own comment says *"class
properties are not for sreaming therefore 'stored' is not supported"*. It was
green because pxx died at `stored` in ANY property — `pascal26:14: error:
expected ':' before 'False'`, at the `stored` token, never reaching a class
property at all. frankS's phrasing is the general one and is better than
"passing for the wrong reason": **a `%FAIL` row satisfied by a blocker UPSTREAM
of its own subject is a guard that cannot fail, and it prints PASS.**

**Gate:** shared with the ticket above — `tools/gate.sh quick` on a DIRTY tree
and `PXX_ALLOW_FULL_SUITE=1 make test`.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
