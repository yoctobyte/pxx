---
title: Classes & interfaces
order: 22
---

# Classes & interfaces

PXX supports Object Pascal classes: single inheritance, virtual methods with
dynamic dispatch, constructors/destructors, visibility sections, and properties.
The example below compiles and runs on the pinned compiler.

## Declaring a class

```pascal
type
  TAnimal = class
  protected
    FName: string;
  public
    constructor Create(const AName: string);
    function Speak: string; virtual;
    property Name: string read FName;
  end;
```

- Classes are **reference types** — a variable holds a pointer to a
  heap-allocated instance.
- **Visibility sections**: `private`, `protected`, `public`, `published`.
- A field convention of `F`-prefixed names backing a `property` is standard.

## Constructors and instantiation

`Create` allocates and initializes; call it on the class itself. Free the
instance with the built-in `Free` (nil-safe):

```pascal
a := TDog.Create('Rex');
...
a.Free;
```

## Inheritance and virtual methods

A descendant lists its parent in parentheses and `override`s virtual methods.
Dispatch is dynamic — the method matching the *runtime* type runs, even through a
base-class variable:

```pascal
type
  TDog = class(TAnimal)
  public
    function Speak: string; override;
  end;
```

## Properties

A `property` exposes a field through `read`/`write` accessors (a field name or a
method). Read-only properties omit `write`. Indexed (`array`) and `default`
properties are also supported.

```pascal
property Name: string read FName;
```

## Full example

```pascal
program classes_demo;
type
  TAnimal = class
  protected
    FName: string;
  public
    constructor Create(const AName: string);
    function Speak: string; virtual;
    property Name: string read FName;
  end;

  TDog = class(TAnimal)
  public
    function Speak: string; override;
  end;

constructor TAnimal.Create(const AName: string);
begin
  FName := AName;
end;

function TAnimal.Speak: string;
begin
  Result := '...';
end;

function TDog.Speak: string;
begin
  Result := 'Woof';
end;

var
  a: TAnimal;
begin
  a := TDog.Create('Rex');
  writeln(a.Name, ' says ', a.Speak);
  a.Free;
end.
```

Output:

```
Rex says Woof
```

`a` is typed `TAnimal` but holds a `TDog`; `a.Speak` resolves to `TDog.Speak`
through the virtual method table.

## Interfaces

PXX also supports interfaces (reference-counted abstract contracts a class can
implement). Cast with `as` and test with `is`.

## Next

- [Types](./types.md)
- [Back to the language reference](./index.md)
