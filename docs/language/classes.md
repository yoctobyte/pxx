---
title: Classes & interfaces
order: 43
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

## Interfaces (CORBA-style)

PXX supports CORBA-style interfaces on all targets, matching the behavior of Free Pascal's `{$interfaces corba}` mode.

### Key Characteristics

- **No automatic reference counting**: Unlike COM-style interfaces, CORBA-style interfaces in PXX do not perform automatic reference counting (ARC). There is no implicit `_AddRef` or `_Release` call, and the compiler does not automatically free implementing class instances when interface references go out of scope. You must manage the lifecycle of the underlying class instances manually.
- **Fat pointers**: An interface value is represented internally as a two-word fat pointer containing:
  1. A pointer to the interface method table (IMT).
  2. A pointer to the underlying class instance.
- **Interface inheritance**: Interfaces can inherit from other interfaces. A class implementing a derived interface must implement all methods of that interface and its ancestors.
- **Implicit coercion**: A class instance can be assigned directly to an interface variable of an interface it implements, or passed to a routine parameter expecting that interface. The compiler performs the coercion automatically.
- **Checked casting & type checks**:
  - Use `obj is IMyInterface` to check if a class instance implements an interface.
  - Use `obj as IMyInterface` to cast a class instance to an interface. A failed cast traps at runtime.
  - Comparing interface values (`iface1 = iface2`) or comparing against `nil` (`iface1 = nil`) is fully supported.
  - Interface-to-class casting is not supported.

### Interfaces Example

The following example compiles and runs on the pinned compiler:

```pascal
program interfaces_demo;

type
  IReadable = interface
    function ReadStr: string;
  end;

  IWritable = interface
    procedure WriteStr(const S: string);
  end;

  // Interface inheritance
  IDocument = interface(IReadable)
    function GetTitle: string;
  end;

  // TDocument implements IDocument (and implicitly IReadable) and IWritable
  TDocument = class(IDocument, IWritable)
  private
    FTitle: string;
    FContent: string;
  public
    constructor Create(const ATitle: string);
    function ReadStr: string;
    function GetTitle: string;
    procedure WriteStr(const S: string);
  end;

constructor TDocument.Create(const ATitle: string);
begin
  FTitle := ATitle;
  FContent := '';
end;

function TDocument.ReadStr: string;
begin
  Result := FContent;
end;

function TDocument.GetTitle: string;
begin
  Result := FTitle;
end;

procedure TDocument.WriteStr(const S: string);
begin
  FContent := S;
end;

var
  doc: TDocument;
  reader: IReadable;
  writer: IWritable;
begin
  doc := TDocument.Create('PXX Design Manual');

  // Implicit coercion on assignment
  writer := doc;
  writer.WriteStr('CORBA-style interfaces are lightweight.');

  // Checked casting via 'as'
  reader := doc as IReadable;
  writeln(doc.GetTitle, ': ', reader.ReadStr);

  // Type checking via 'is'
  if doc is IDocument then
    writeln('doc implements IDocument');

  // Clean up the class instance manually
  doc.Free;
end.
```

Output:

```
PXX Design Manual: CORBA-style interfaces are lightweight.
doc implements IDocument
```

## Next

- [Types](./types.md)
- [Back to the language reference](./index.md)
