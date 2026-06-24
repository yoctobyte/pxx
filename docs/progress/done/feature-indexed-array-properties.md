# Indexed (array) properties + `default` — `property Items[i]: T read G write P`

- **Type:** feature (parser / properties) — language
- **Status:** urgent (Track A) — gates the standard Classes surface
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** [[feature-own-net-http-lib]] / Classes work — building `TList` /
  `TStrings` / `TStringList`.

## Symptom

Indexed (array) properties are not parsed:

```pascal
type T = class
  FI: array of Pointer;
  function G(i: Integer): Pointer;
  property Items[i: Integer]: Pointer read G;          { ERROR }
  property Items[i: Integer]: Pointer read G; default; { ERROR }
end;
```
→ `Expected: :, but got: ` at the `[` of the property declaration. Simple
(non-indexed) properties work. No rtl/pcl unit currently uses an indexed
property — the feature is unbuilt.

## Why it matters (high value)

This is the standard idiom for every collection, so it gates a lot:

- **Classic Classes** (the agreed traditional path): `TStrings.Strings[Index]`
  (the `default` property → `list[i]`), `TStrings.Objects[Index]`,
  `TList.Items[Index]` (default). Without it `TList`/`TStringList` can only
  expose `Get(i)`/`Put(i,v)` methods — non-idiomatic and **incompatible with FPC
  code**.
- **Synapse** consumes them directly: `blcksock.pas` uses
  `SocketList.Items[n]` (and `TList`/`TStringList`), so the Classes cascade
  (synsock → blcksock) needs this.
- A future **`Generics.Collections`** (`TList<T>.Items[]`) needs it too.

## Scope

- Parse `property Name[Index: TIdx]: TElem read Getter [write Setter];` where
  Getter is `function(Index): TElem` and Setter `procedure(Index; Value)`.
- `default;` on an indexed property → `obj[i]` lowers to the default indexed
  property's getter/setter.
- Multi-index (`property P[a, b: Integer]: T`) is a nice-to-have; single index
  covers the Classes/collections need first.
- Read-only (no `write`) must be allowed.

## Done when

- The repro above compiles; `t.Items[1]` and (with `default`) `t[1]` read/write
  through the accessors.
- A regression test under `make test` (indexed get/set, default `[i]`, read-only).
- Self-host fixedpoint byte-identical, `make stabilize` + `make pin` so Track B
  can build the standard Classes ([[feature-own-net-http-lib]] follow-on / the
  Classes unit).

## Log
- 2026-06-24 — DONE (Track A). Indexed (array) properties + `default` land:
  `property Items[i: TIdx]: T read G [write P]; [default;]`. Front-end only
  (parser + symtab), no codegen change → self-host fixedpoint byte-identical.
  - Decl: parse + discard the `[index: TIdx]` clause (the accessor signature
    defines the index type), set `UPropIsIndexed`; optional trailing `default;`
    sets `UPropIsDefault`.
  - Access (`obj.Items[i]` read/write): the property branch in `ParseLValueAST`
    parses the subscript and threads it as an extra accessor arg (getter: self,
    index; setter: self, index, value). `:=` detection peeks PAST the bracket
    group (the `:=` follows the subscript, not the name).
  - `default` (`obj[i]`): the class-index branch routes through `FindDefaultProp`
    to the default property's getter/setter; getter result `continue`s the
    postfix loop (so `list[i].field` works) with the property's element type.
  - Read-only (no `write`) supported.
  - Regression: `test/test_indexed_property.pas` (indexed get/set, default `[i]`,
    read-only) wired into `make test` (test-core).
  Multi-index (`P[a,b: T]`) still nice-to-have (single index covers the
  collections need). Unblocks the standard Classes surface (TList/TStringList
  Items[], Synapse SocketList.Items[n]).
- 2026-06-24 — Multi-index (`property Cells[a, b: Integer]: T`) landed too:
  `ParsePropIndexArgs` parses `[e1 {, e2}]` into an AN_ARG chain spliced between
  self and (setter) value; works for `obj.Cells[a,b]` and default `obj[a,b]`,
  read + write. Test extended (2D grid get/set + default). Front-end only,
  byte-identical. The feature is now fully complete.
