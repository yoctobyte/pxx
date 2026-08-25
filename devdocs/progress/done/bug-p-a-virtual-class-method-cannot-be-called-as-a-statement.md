---
slug: bug-p-a-virtual-class-method-cannot-be-called-as-a-statement
title: "A virtual CLASS method invoked for effect is rejected as `statement is neither a call nor an assignment`"
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "Five copies of the same `is this node a call?` test each listed AN_CALL / AN_VIRTUAL_CALL / AN_INTF_CALL / AN_CALL_IND and every one of them forgot AN_CLASS_VIRTUAL_CALL, so `TFoo.Bump;` — a virtual class method called for its side effect, not its result — was refused at statement level. FIXED this session by normalising the five copies onto one predicate."
---

# Symptom

```pascal
type
  TBase = class public class procedure Bump; virtual; end;
  TDer  = class(TBase) public class procedure Bump; override; end;
var c: TBaseClass;
begin
  c := TDer;
  c.Bump;      { <-- statement is neither a call nor an assignment }
end.
```

Assigning the result of a virtual *function* class method was fine; only the
statement position failed, and only for the CLASS-virtual dispatch kind.

# Root cause — the double case, five times over

`compiler/pasparser_stmt.inc` carried **five** hand-written copies of

```pascal
if (ASTKind[n] = AN_CALL) or (ASTKind[n] = AN_VIRTUAL_CALL)
   or (ASTKind[n] = AN_INTF_CALL) or (ASTKind[n] = AN_CALL_IND) then
```

and not one of them mentioned `AN_CLASS_VIRTUAL_CALL`, which was added later.
Textbook `devdocs/dev/normalise-dont-special-case.md`: the fifth arm is the one
that stays broken because nobody greps for the sibling.

# Fix (landed 2026-08-25)

New `ASTNodeIsCall(node): Boolean` in `compiler/symtab.inc` naming all five kinds
once; the five copies in `pasparser_stmt.inc` now call it. Any future call kind
is added in one place.

Regression test `test/test_virtual_class_method_called_as_a_statement.pas`,
`.expected` from fpc 3.2.2.

# Where it was found

[[feature-pascal-corpus-generics]], wall at `generics.defaults.pas:1865`.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
