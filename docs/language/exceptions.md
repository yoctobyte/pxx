---
title: Exceptions
order: 47
---

# Exceptions

PXX implements setjmp-style exceptions with a per-stack handler chain. It supports both exception handling (`try ... except`) and resource cleanup (`try ... finally`).

## Raising and Handling Exceptions

### Raising an Exception
Use the `raise` statement followed by a class instance to raise an exception:

```pascal
raise TMyException.Create;
```

Inside an `except` block, a bare `raise` statement re-raises the active exception:

```pascal
except
  on E: TMyException do
  begin
    Log(E);
    raise; { re-raise }
  end;
end;
```

### Try-Except Blocks
A `try ... except ... end` block catches exceptions raised within the `try` clause. You can use typed handlers to catch specific exception classes:

```pascal
try
  DoSomething;
except
  on E: TSpecificException do HandleSpecific(E);
  on E: TObject do HandleFallback(E);
end;
```

### Try-Finally Blocks
A `try ... finally ... end` block ensures that the statements in the `finally` clause execute regardless of whether an exception was raised inside the `try` clause. This is typically used for resource cleanup:

```pascal
var
  doc: TDocument;
begin
  doc := TDocument.Create;
  try
    doc.Process;
  finally
    doc.Free; { always executes }
  end;
end;
```

---

## Key Characteristics & Limitations

### 1. No Built-in Exception Hierarchy
Unlike Free Pascal or Delphi, PXX does **not** bundle a predefined `Exception` class hierarchy (such as `Exception`, `EExternal`, `EAbort`, etc.) with message constructors. 
- You must supply the classes you intend to raise and catch.
- Any user-defined class can be raised and caught.

### 2. Automatic Resource Cleanup (Unwinding)
When an exception is raised, the runtime unwinds the stack frames until a matching handler is found. During unwinding, the compiler automatically calls the appropriate cleanup code (releasing reference counts) for any **managed local variables** (such as managed `string`s, dynamic arrays, and records with managed fields) in the unwound frames, preventing memory leaks.

### 3. Unhandled Exceptions
If an exception is raised and no handler catches it, the runtime's default unhandled-exception reporter prints a diagnostic message to standard error and terminates the program with a non-zero exit code.
- Pass `--no-unhandled-handler` (or `-fno-unhandled-handler`) to the compiler to make unhandled exceptions exit silently with status `1`.

### 4. Interaction with Generators
Because exception frames are tied to the call stack, calling `yield` from within a `try`, `except`, or `finally` block inside a generator is **rejected** by the compiler.

---

## Compiling Example

The following example compiles and runs on the pinned compiler:

```pascal
program exceptions_demo;

type
  TValidationException = class
  private
    FReason: string;
  public
    constructor Create(const AReason: string);
    property Reason: string read FReason;
  end;

constructor TValidationException.Create(const AReason: string);
begin
  FReason := AReason;
end;

procedure ValidateAge(Age: Integer);
begin
  if (Age < 0) or (Age > 150) then
    raise TValidationException.Create('Age is out of realistic range');
end;

procedure RunValidator;
begin
  try
    writeln('Validating age...');
    ValidateAge(200);
    writeln('Validation passed.'); { will not run }
  except
    on E: TValidationException do
    begin
      writeln('Validation failed: ', E.Reason);
      E.Free; { free the exception instance }
    end;
  end;
end;

begin
  RunValidator;
end.
```

Output:

```
Validating age...
Validation failed: Age is out of realistic range
```
