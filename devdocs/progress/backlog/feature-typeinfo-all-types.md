---
prio: 50
---

# `TypeInfo(T)` for every type, not just enums

- **Type:** feature (RTTI — Track A/P)
- **Status:** backlog — filed 2026-07-14.
- **Blocks:** [[feature-pascal-corpus-generics]] (generics.defaults selects a
  comparer per TypeInfo(T), including TypeInfo of a GENERIC PARAMETER),
  [[feature-typinfo-facade-unit]], and behind those the RTTI->streaming->LFM
  line and [[feature-embed-dwscript-rtti]].

## Today
`TypeInfo(X)` accepts ENUM types only — deliberately: we emit one blob per enum
type (name, count, member names) and refused everything else rather than hand
back a blob whose layout is ours while pretending it is FPC's. That refusal was
right, and it stays right; what changes is that WE now supply the typinfo unit
that reads the blobs ([[feature-typinfo-facade-unit]]), so our layout is fine
and the only thing missing is the blobs themselves.

## The work
Emit a per-TYPE info blob for the kinds real code asks about:
- ordinals (with their sub-kind + range), Char/Boolean
- floats (with the float sub-kind)
- strings (short/ansi), sets, arrays (element type + length), dyn arrays
- records (size; field walk if/when a consumer needs it)
- classes (we already have the class RTTI blob — point at it) and metaclasses
- **generic parameters at SPECIALIZATION time** — `TypeInfo(T)` inside a
  `TList<Integer>` body must yield Integer's blob. This is the interesting part
  and the reason the ticket exists.
- interfaces, method pointers: only when a consumer needs them.

Interned per type, addressed like the enum blobs (data-ref sentinel patched at
link time), so the cost is paid once and only by programs that ask.

## Gate
`make test` + self-host byte-identical; a b-test that reads TypeInfo of each
kind through the facade unit; fpjson suite stays green.
