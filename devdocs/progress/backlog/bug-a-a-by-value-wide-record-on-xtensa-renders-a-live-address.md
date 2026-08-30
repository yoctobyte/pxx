---
slug: bug-a-a-by-value-wide-record-on-xtensa-renders-a-live-address
track: A+S
prio: 65
type: bug
status: open
found: 2026-08-30
---

# A by-value wide record on xtensa renders a live address as a decimal number

`test_arm32_record_byval_wide` prints `134730463` where the oracle says `8`. That is **a
live address rendered as a decimal integer** — the value was never dereferenced.

Measured by frankS at HEAD `fa01f7111`, compiler `a6b4e6e1816c`, Call0 profile.

## The pattern this belongs to, which is the reason it is worth 65

**This is the exact signature of the var-string-parameter bug frankS fixed at the start of
the same night, now appearing on a different parameter class.** Same shape — a parameter
passed as a reference where the callee expects a value, printed as its own address —
different parameter class: by-value **wide records** instead of `var` strings.

That pattern held all night across several findings. It is the `normalise-dont-special-case`
shape at the ABI layer: **one concept (how a parameter arrives) served by per-class
mechanisms, so a fix on one class leaves the others.** Before fixing this one, enumerate
the parameter classes that reach the same lowering and check each — a fix that closes only
by-value wide records is the third arm of a case that has already bitten twice.

Related, same night, same handback: `bug-a-a-shortstring-write-on-xtensa-corrupts-a-
neighbouring-variable`. Both are wrong-value, both on xtensa Call0.

## Filed rather than left as a table row

See the sibling ticket's note. frankS named this in the handback partition and deliberately
did not file it; I am filing it because **the ranker reads frontmatter and a prose row has
no owner.** The judgment that four thin tickets are worse than one honest table is right in
general and wrong for wrong-value bugs specifically.
