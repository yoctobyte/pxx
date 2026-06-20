# Hardcoded 'TMyClass' name clash in compiler type resolution

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** Surfaced while writing test cases for class field dynamic arrays of strings in PCL.

## Problem

The compiler fails to compile any user-defined class named `TMyClass` when attempting to call its methods, yielding the following error:
```
Expected: :=, but got:  (Kind: 74, Line: <N>)
pascal26:<N>: error: unexpected token ()
```

This happens because the name `TMyClass` is hardcoded as a built-in record ID in the compiler's type resolution logic. When a user defines a class named `TMyClass`, the compiler parses the definition but then maps the type of variables declared with this type to the built-in record ID `REC_TMYCLASS` (which is `10`) rather than the user class index. Consequently, method selector lookups on the instance fail, and the parser mistakenly treats the method call statement as an invalid field assignment.

## Root Cause

In `compiler/symtab.inc`, the function `IsClassType` has hardcoded checks for `'TMyClass'`:
```pascal
function IsClassType(const lo: AnsiString): Boolean;
var ci: Integer; lo2: AnsiString;
begin
  Result := False;
  if (lo = 'TMyClass') or (lo = 'tmyclass') then Result := True;
  ...
```

And in `compiler/parser.inc` around line 6748 (`ParseTypeKind`):
```pascal
        else if IsClassType(lo) then
        begin
          if CaseEqual(lo, 'TMyClass') then
            LastTypeRecId := REC_TMYCLASS
          else
          ...
```

Because `LastTypeRecId` is set to `REC_TMYCLASS` (which has the value `10`, below `REC_UCLASS_BASE`), the compiler bypasses user class method lookups during selector parsing in `ParseLValueAST`.

## Workaround

Do not name user-defined classes `TMyClass`. Use a different name (e.g. `TTestContainer` or `TMyContainer`).

## Fix Direction

Remove the hardcoded references to `'TMyClass'` and `REC_TMYCLASS` from the compiler source files (`compiler/symtab.inc`, `compiler/parser.inc`, etc.) and ensure that `TMyClass` is resolved dynamically as a user class like any other type.

## RESOLVED 2026-06-20 (Track A)

Removed the hardcoded `'TMyClass'` -> REC_TMYCLASS mappings from IsClassType +
IsRecordType (symtab.inc) and ParseTypeKind (parser.inc). A user class named
TMyClass now resolves as a normal user class (REC_UCLASS_BASE+ci), so method
calls work. The REC_TMYCLASS=10 constant and its dead builtin-layout self-check
stay (harmless; RecSize still returns 16) to avoid renumbering the bootstrap-
stable REC_* ordinals. test/test_class.pas (declares TMyClass) still passes via
user-class resolution; test/test_tmyclass_name.pas adds the method-call case.
Byte-identical self-host, make test green.
