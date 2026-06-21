# `for-in` over a qualified set member source fails

- **Type:** bug (compiler / parser)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-21
- **Relation:** next `examples/adventure` blocker after the text-file surface is
  made visible; sibling to `feature-forin-member-access-source` and
  `feature-for-in-iteration`.

## Symptom

After importing the PAL-backed `textfile` unit explicitly and compiling
adventure with the POSIX platform path, the demo gets past `Assign` and stops at
the save path:

```pascal
for sp in Player.Spells do
  WriteLn(f, 'spell=' + LowerStr(SpellName(sp)));
```

```text
pascal26:567: error: for-in: variable is not a string or array ()
```

Other similar uses exist in the inventory UI:

```pascal
for sp in g.Player.Spells do ...
```

`Player.Spells` is a qualified member-access expression whose type is
`TSpellSet = set of TSpell`.

## Root Cause

Set iteration itself is implemented (`feature-for-in-iteration`), and qualified
member-access for-in sources are implemented for arrays/strings
(`feature-forin-member-access-source`). The node-based classifier used for
qualified sources still routes only string/array metadata; it does not recover
set element metadata for a set-valued field expression.

## Direction

- Extend the node-based for-in source classifier to recognize set-valued
  qualified lvalues (`obj.field`, `Self.field`, nested fields).
- Recover the element enum type/range for the field's set type, equivalent to
  the existing symbol-based `SymSetEnumId` path for plain set variables.
- Reuse the existing set-membership scan lowering: iterate ordinals and execute
  the body only when `ord in setExpr`.
- Keep array/string member-access for-in behavior unchanged.

## Acceptance

- A minimal program with `for e in obj.SetField do ...` over `set of <enum>`
  prints members in ordinal order.
- `for e in Self.SetField` and a nested member source also work, if practical.
- `examples/adventure` gets past `for sp in Player.Spells`.
- Existing for-in tests stay green.

## Log

- 2026-06-21 - Opened from the adventure compile path. The previous member-access
  for-in ticket was array/string focused; this covers set-valued qualified
  sources specifically.
- 2026-06-21 - DONE (Track A). The set membership-scan desugar was extracted from
  `ParseForInSetAST` into a reusable `BuildForInSetLoop(varIdx, setEnumId,
  setElemTk, setOperand, bodyNode)` that takes an abstract set value node.
  `ParseForInNodeAST` (the qualified member-access source path) now recovers the
  set element enum/range — for an `AN_IDENT` source from `SymSetEnumId/ElemTk`,
  for an `AN_FIELD` source from two new parallel arrays `UFldSetEnumId/ElemTk`
  (captured in `AddUField` from `LastTypeSetEnumId/ElemTk`, mirroring the
  symbol/property paths) — and routes `set`-valued sources to `BuildForInSetLoop`
  over `CloneAST(contNode)` before the array/string classifier. `for sp in
  g.Player.Spells` (nested member access) and `for sp in Self.Field` both work.
  Regression test `test/test_forin_set_member.pas`. `make test` green; self-host
  + threadsafe fixedpoint byte-identical.

**Resolved-in:** 085be11 (finalizing commit)
