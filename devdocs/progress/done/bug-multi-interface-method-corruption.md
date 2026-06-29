# Memory/String corruption when calling methods on secondary interfaces

- **Type:** bug
- **Status:** done
- **Track:** A (compiler)
- **Owner:** —
- **Opened:** 2026-06-26 (discovered during Track D documentation validation)

## Symptoms

When a class implements multiple interfaces, calling a method through a secondary interface (i.e., not the first interface in the class heritage list) results in memory/string corruption.

For example, in this hierarchy:
```pascal
type
  IReadable = interface
    function ReadStr: string;
  end;

  IWritable = interface
    procedure WriteStr(const S: string);
  end;

  IDocument = interface(IReadable)
    function GetTitle: string;
  end;

  TDocument = class(IDocument, IWritable)
    // implements ReadStr, GetTitle, and WriteStr
  end;
```

If we assign a `TDocument` instance to an `IWritable` variable:
```pascal
var
  doc: TDocument;
  writer: IWritable;
begin
  doc := TDocument.Create('Title');
  writer := doc; // Coercion to secondary interface
  writer.WriteStr('Some content'); // <-- Triggers corruption/incorrect self pointer
```
Calling `writer.WriteStr` results in corrupted string values in fields or other memory locations, indicating that the `self` pointer passed to the method or the field offset lookup inside the method is incorrect.

In contrast, calling methods on the first interface (`IDocument` or its parent `IReadable`) works perfectly without any corruption.

## Root Cause Hypothesis

In CORBA-style interfaces, an interface value is a fat pointer `{IMT, instance}`.
When a class implements multiple interfaces, each interface has its own IMT. When invoking a method via an interface fat pointer, the compiler must adjust the `self` pointer (the `instance` field of the fat pointer) to point to the correct offset of the class instance or adjust the field offsets accordingly.
If the compiler does not correctly calculate or apply this `self` adjustment for secondary interfaces in the heritage list, the method will execute with an incorrect `self` pointer, leading to field writes/reads targeting wrong memory offsets (hence the corruption).

## Actual Root Cause

The fat pointer and secondary IMT selection were correct. The corruption came
from interface-call argument finalisation: `AN_INTF_CALL` built `IR_CALL_IND`
directly, bypassing the direct-call path that binds non-lvalue managed-string
arguments to a hidden owning `tyAnsiString` temp. A secondary interface method
like `WriteStr(const S: string)` therefore received a frozen string literal
pointer and stored that raw backing blob into a managed-string field.

## Steps to Reproduce

See the test case in `scratch/test_interfaces_demo.pas` under the active conversation directory.

## Acceptance

- Interface method dispatch on classes implementing multiple interfaces (both primary and secondary) works correctly without memory corruption.
- Verified by a test case compiling and running successfully on all targets.

## Resolution

- `AN_INTF_CALL` now applies the same hidden-temp managed-string argument binding
  used by direct calls.
- Added `test/test_interfaces_multi_secondary.pas`, covering direct baseline,
  secondary-interface mutation, inherited-interface reads, and direct field reads.
- Wired the regression into native, i386, aarch64, and arm32 test slices.

Verified:

```
make compiler/pascal26
make test-core
make test-i386
make test-aarch64
make test-arm32
```

## Log

- 2026-06-29 — resolved; commit in this changeset.
