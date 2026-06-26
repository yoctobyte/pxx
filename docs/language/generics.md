---
title: Generics
order: 46
---

# Generics

PXX supports Object Pascal generics, allowing you to write type-independent functions, procedures, and classes. 

## Specialization Model

PXX uses a strict **explicit named specialization** model. 
- You must explicitly specialize a generic template and give it a concrete name before calling or instantiating it.
- There is no implicit call-site specialization (such as `Max<Integer>(A, B)`); you must specialize the routine first and call the specialized version.

Specialization is supported in two forms:
1. **Top-level form**: Specializing a generic function or class in the global scope using `specialize Name<Type> as SpecializedName`.
2. **Type-section form**: Specializing a generic class inside a `type` declaration block.

---

## Generic Functions and Procedures

Declare a generic routine by prefixing it with the `generic` keyword and listing its type parameters in angle brackets (`<T>`):

```pascal
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;
```

To use it, specialize it in the global scope:

```pascal
specialize Max<Integer> as MaxInt;
specialize Max<Double> as MaxDouble;
```

Then call the specialized routines like ordinary functions:

```pascal
var
  i: Integer;
begin
  i := MaxInt(10, 20);
end;
```

---

## Generic Classes

Declare a generic class by prefixing it with the `generic` keyword:

```pascal
type
  generic TBox<T> = class
  private
    FValue: T;
  public
    constructor Create(const AVal: T);
    function GetValue: T;
  end;
```

Implement the methods by referencing the generic type parameters:

```pascal
constructor TBox.Create(const AVal: T);
begin
  FValue := AVal;
end;

function TBox.GetValue: T;
begin
  Result := FValue;
end;
```

Specialize the generic class inside a `type` section or at the top level:

```pascal
type
  TIntBox = specialize TBox<Integer>;
  TStrBox = specialize TBox<string>;
```

---

## Compiling Example

The following example compiles and runs on the pinned compiler:

```pascal
program generics_demo;

// 1. Generic Function
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;

// Explicit top-level specialization
specialize Max<Integer> as MaxInt;

// 2. Generic Class
type
  generic TKeyValuePair<TKey, TValue> = class
  private
    FKey: TKey;
    FValue: TValue;
  public
    constructor Create(const AKey: TKey; const AValue: TValue);
    property Key: TKey read FKey;
    property Value: TValue read FValue;
  end;

constructor TKeyValuePair.Create(const AKey: TKey; const AValue: TValue);
begin
  FKey := AKey;
  FValue := AValue;
end;

type
  // Explicit type-section specialization
  TIntStrPair = specialize TKeyValuePair<Integer, string>;

var
  pair: TIntStrPair;
begin
  writeln('Max of 10 and 20: ', MaxInt(10, 20));

  pair := TIntStrPair.Create(1, 'PXX Compiler');
  writeln('Pair: ', pair.Key, ' = ', pair.Value);
  pair.Free;
end.
```

Output:

```
Max of 10 and 20: 20
Pair: 1 = PXX Compiler
```
