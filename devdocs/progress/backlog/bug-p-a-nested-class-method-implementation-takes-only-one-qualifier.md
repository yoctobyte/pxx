---
track: P
prio: 35
type: bug
blocked-by: []
summary: "`function touter.tinner.Tag: string;` — the implementation header of a method belonging to a NESTED class — is a parse error: the header parser takes one qualifier. Declaring and implementing such a method inline works, so this is the out-of-line spelling only."
---

# A nested class's method implementation takes only one qualifier

- **Type:** bug (refusal, FPC-compat) — **Track P**, in the shared
  `compiler/parser.inc`.
- **Found:** 2026-08-16, while fixing
  [[bug-a-duplicate-class-name-check-is-scope-blind]] — nested class TYPES are
  now scoped correctly, and this is the one spelling that still refuses.

## Measured

```pascal
type
  touter = class
  type tinner = class
    function Tag: string;
  end;
  end;
function touter.tinner.Tag: string; begin Result := 'outer'; end;
```

```
pascal26:16: error: unexpected token   (Expected: :, but got: .)
```

FPC 3.2.2 compiles it. `var a: touter.tinner`, `touter.tinner.Create` and the
fields all work as of the fix above — this is only the out-of-line
implementation header.

## Where

The implementation-header parser reads `Name.Method` and stops; a second dot
is not expected. It should walk the same nested-type registry the type and
constructor paths now use (`FindNestedType`, `compiler/parser.inc`), taking
qualifiers until the last one, which is the method name.

## Why it is filed rather than folded in

It is a different parser (declaration headers, not expressions or type names),
and the fix it belongs with was already three sites wide. Keeping it separate
keeps that one reviewable — and this refuses loudly, which is the safe failure.

## Gate

Extend `test/test_nested_class_type_scoping.pas` with an out-of-line method on
each of the two `tinner` classes, asserting each returns its OWN tag (that is
also what proves the qualifier picks the right class, not just that it parses);
diff against FPC; `tools/gate.sh quick`.
