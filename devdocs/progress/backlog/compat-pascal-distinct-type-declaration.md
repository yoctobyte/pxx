---
track: P
prio: 25
type: compat
status: open
found: 2026-08-29
found-by: claude-N
---

# `type T = type byte;` — the distinct-type declaration is not parsed

```pascal
type TMyB = type byte;
var x: TMyB; c: cardinal;
begin c := $12345678; x := 5; WriteLn(x, ' ', TMyB(c)); end.
```

FPC: `5 120`. pxx: `error: unknown type: type` at the declaration.

`type T = type Base` declares a type that is layout-identical to `Base` but
DISTINCT from it for overload resolution, RTTI identity and `var`-parameter
matching — the standard Pascal idiom for a strong typedef. Plain
`type T = Base` (an alias) parses fine; only the `= type` form does not.

Loud, so ranked low per CLAUDE.md's compat table ("FPC accepts a form we
reject" → compat, ranked by how much real code uses it). It is common in FPC
RTL headers and in Delphi-lineage code, so it will recur.

Found beside [[bug-p-a-cast-through-an-ordinal-type-alias-does-not-truncate]]
while reducing rung 3 of [[feature-pascal-corpus-oop]] — deliberately filed
apart, because that one is a silent wrong value and this one is a parse error,
and folding a loud gap into a silent bug is how the silent half gets lost.

## Gate

The program above matching FPC, plus a check that the distinct type is actually
distinct where that is observable (a `var` parameter of `Base` must not accept a
`T`, once overload/parameter matching is in scope).
