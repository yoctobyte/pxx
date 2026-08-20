---
track: C
prio: 60
type: bug
blocked-by: []
summary: "`s.f[i](args)` / `p->f[i](args)` -- a dispatch table held in a struct field, the ordinary C vtable -- failed to parse at any scope. CalleeSig had an arm for AN_INDEX over an AN_IDENT and one for a scalar AN_FIELD, but none for an AN_INDEX over an AN_FIELD. Fixed together with the local-array half; full write-up in the sibling ticket."
status: done
owner: frank1-ACP
---

# A struct-field function-pointer array is not callable

Found and fixed 2026-08-20 in the same sitting, and by the same gcc
differential probe, as its sibling. The measurement table, both root causes,
the test and the gate are written up once, in:

**`done/bug-c-a-local-typedef-d-function-pointer-array-is-not-callable.md`**

This ticket exists so that slug resolves — the code comment in
`compiler/cparser.inc` (the new `AN_INDEX` over `AN_FIELD` arm of `CalleeSig`)
and `test/cfnptr_array_callable.c` both name it.

In one line: `CalleeSig` gained an arm for an `AN_INDEX` whose left is an
`AN_FIELD`, reading the field's per-element signature from
`RecFieldElemProcSig` — the same channel `(*s.pf)(args)` already used — with a
fallback to `RecFieldProcSig`.
