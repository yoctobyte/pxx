---
title: Generics
order: 46
---

# Generics

PXX supports Object Pascal generics, allowing you to write type-independent functions, procedures, and classes. 

## Specialization Model

A generic template is always specialized with concrete type arguments before it
is called or instantiated. There is no *implicit* specialization — the type
arguments are always written out, never inferred from the call's arguments
(`Max(A, B)` alone never picks `T` for you).

Specialization is supported in three forms:
1. **Top-level form**: Specializing a generic function or class in the global scope using `specialize Name<Type> as SpecializedName`.
2. **Type-section form**: Specializing a generic class inside a `type` declaration block.
3. **Inline form**: Specializing a generic *routine* at the call site,
   `specialize Name<Type>(Args)`, in expression or statement position. This is
   what FPC code in the wild writes.

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

Or specialize it **inline at the call site**, which needs no name of its own —
useful when a unit uses one generic routine on several types and would otherwise
carry an identifier per (routine, type) pair:

```pascal
begin
  WriteLn(specialize Max<Integer>(3, 9));   { expression position }
  specialize Swap<string>(S1, S2);          { statement position  }
end.
```

The two spellings produce one specialization per (routine, type) pair, and can
be mixed freely in the same program.

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
