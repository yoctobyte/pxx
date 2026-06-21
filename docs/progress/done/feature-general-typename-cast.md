# General `TypeName(expr)` reinterpret cast (named record/class/pointer)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18
- **Split from:** [[feature-explicit-typecasts]] (scope §3). The cast-token
  allowlist gap (`Char`/`Boolean`/`String`) is closed there; this is the larger,
  separate piece deferred at resolution.

## Motivation

PXX casts are still a fixed token allowlist in the factor parser
(`Integer`/`LongWord`/`Char`/`Boolean`/`String`/`Pointer`/`Ord`/`Chr`/`PChar`).
There is no general `TypeName(expr)` form for a **user-named** type — i.e. a
reinterpret/checked cast to a named record, class, pointer-to-T, or type alias:

```pascal
TFoo(p)^           { pointer reinterpret to a named record }
TDerived(baseObj)  { downcast a class reference (unchecked here; `as` is checked) }
PMyRec(addr)       { typed-pointer reinterpret }
```

Today these only work for the hardcoded builtins; a `TypeName(expr)` with a
user type name falls through to "expected expression" or is misparsed.

## Scope

- In the factor parser, when an identifier in value position is a **known type
  name** (record/class/alias/typed-pointer) and is immediately followed by
  `(expr)`, build a reinterpret-cast node carrying the target type (reuse the
  existing `AN_PTR_CAST` machinery / type-alias `AliasElemTk` path where it
  fits). No value conversion — same bits, new static type — except where a
  checked form is wanted.
- Disambiguate from a call: a type name followed by `(` is a cast; a routine
  name is a call. Constructor calls (`TFoo.Create`) are unaffected.
- Decide interaction with `is`/`as` ([[feature-class-is-as]]): `as` is the
  *checked* class cast; `TClass(obj)` is the *unchecked* reinterpret. Keep them
  distinct (matches FPC/Delphi).

## Acceptance

- `TRec(ptr)^.field`, `PRec(addr)`, and `TClass(obj).method` compile and
  reinterpret correctly on all targets; `make test` + `make cross-bootstrap`
  stay byte-identical. Add an oracle test (output-equality vs FPC).

## Notes

- Lower-value than `is`/`as` (which is the real OOP gap); schedule after the
  class-cast work so the checked/unchecked split is designed together.

## Log
- 2026-06-18 — surveyed during the autonomous run. **Pointer-type-alias casts
  already work** end to end: `PFoo(expr)`, `PFoo(expr)^.field`, `PFoo(addr)[i]`
  via the AN_PTR_CAST branch in ParseFactor (with its own ^/./[] suffix loop).
  So the record-via-pointer reinterpret case (`PRec(addr)^`) is covered today.
  **Still open:** the bare unchecked **class** reinterpret `TClass(obj)` with a
  trailing `.member` — needs class-cast detection in ParseFactor plus postfix
  member/method integration on the cast result. Low value: the *checked* form
  `(obj as TClass).member` already works (feature-class-is-as), and unchecked
  reinterpret is mainly for type-punning. Deferred behind the float-correctness
  bugs (feature-int-to-float-assign, feature-result-in-loop).

## RESOLVED 2026-06-20 (Track A)

All the acceptance forms now work:
- `PRec(addr)` typed-pointer reinterpret — already worked (pointer-alias cast).
- `TClass(obj).method` / `.field` — already worked (AN_CLASS_CAST).
- `TRec(ptr)^.field` record-name reinterpret — ADDED, read and write. A record
  name followed by `(` is reinterpreted as a pointer to that record; the pointee
  rec id is carried on the AN_DEREF node (ResolveNodeRec AN_DEREF ASTIVal>0 path)
  so trailing `.field` offsets resolve. Added in both the factor parser
  (expression/read) and the statement parser (lvalue/write), mirroring the
  existing class- and pointer-alias-cast branches.

Verified: `TRec(p)^.a/.b` read and `TRec(p)^.a := v` write hit the right field
offsets. make test + cross-bootstrap (i386/aarch64/arm32) byte-identical;
test/test_record_typecast.pas added. (A bare value reinterpret `TRec(x)` without
`^` — record value cast — is not part of this; the `^.field` form covers the
typed-pointer use the ticket and Track B reflection/binding code want.)

**Resolved-in:** 453bbc5 (finalizing commit)
