---
prio: 50
---

# A parenthesised expression loses its class id: `(b as T)[i]` and `(b as T).ClassName`

- **Type:** bug (frontend — member/index dispatch on a parenthesised value)
- **Track:** P — Pascal frontend
- **Status:** done
- **Found by:** fcl-json's own test suite ([[feature-pascal-corpus-fpjson]]), which writes
  `AssertEquals('Correct class', AClass, (Data as TJSONArray)[0].ClassType)`.

## Two symptoms, one cause
```pascal
writeln((b as TArr)[1].ClassName);   { IR_UNSUPPORTED: cannot lower AST node (kind 57) }
writeln((b as TD).ClassName);        { prints a NUMBER -- the object pointer -- no error }
```

1. **`(expr)[i]` does not dispatch the DEFAULT PROPERTY.** It builds a raw AN_INDEX instead of
   the getter call, which leaves the AN_AS_CAST orphaned and unlowerable (`kind 57`). The
   direct form `a[1]` works, so it is not the property machinery — it is that the
   parenthesised value arrives with recName = REC_NONE.
2. **`(expr).Member` silently DROPS an unresolvable member** and evaluates to the object
   pointer. Same root: no class id, so nothing matches, and a member on a pointer is accepted
   (see [[bug-pascal-member-access-on-pointer-silently-accepted]]).

`ResolveNodeRec` already knows an AN_AS_CAST's class (`REC_UCLASS_BASE + ASTIVal`), so the
information is there — the parenthesised-expression suffix path in ParseFactor simply does not
ask for it, and does not route through the dispatch that ParseLValueAST and
ParseClassRecordSelectors use.

## The real shape of the fix
This is the THIRD place that re-implements member/index dispatch (ParseLValueAST's suffix loop,
ParseClassRecordSelectors, and ParseFactor's paren-expression tail). The duplication IS the
bug — the same lesson the method-call paths taught (they now share one builder, which is what
fixed `array of const` literals to methods). The paren tail should hand off to
ParseClassRecordSelectors with `ResolveNodeRec(node)`, not grow its own copy.

## Already fixed, and NOT this
Class-reference ops chained after a *value* (`d.M.ClassName`) — that goes through
ParseClassRecordSelectors and now works (b296). Only the PARENTHESISED source is affected.

## Gate
`make test` + self-host byte-identical.

## Log
- 2026-07-13 — resolved, commit pending.
