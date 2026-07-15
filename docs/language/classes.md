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

Properties expose class fields or methods using an intuitive, field-like syntax while maintaining encapsulation. In PXX, properties can be backed directly by fields or by getter/setter methods.

### Field-Backed vs. Method-Backed Properties

- **Field-Backed**: Backed directly by a private or protected field. Reading or writing to the property directly accesses the field.
- **Method-Backed**: Backed by a getter function and/or a setter procedure. The getter must return the property type; the setter must accept the property type as its last parameter.

```pascal
type
  TWidget = class
  private
    FValue: Integer;
    function GetValue: Integer;
    procedure SetValue(AValue: Integer);
  public
    // Field-backed property (read-only in this case)
    property RawValue: Integer read FValue;
    
    // Method-backed property
    property Value: Integer read GetValue write SetValue;
  end;
```

### Indexed (Array) Properties

Indexed properties act like arrays but are backed by getter and setter methods that accept one or more index parameters. They are declared with index specifications inside brackets.

- **Declaration**: `property Name[Index: Type]: Type read Getter write Setter;`
- The getter method must accept the index parameters as its first arguments.
- The setter method must accept the index parameters as its first arguments, followed by the value to write.

```pascal
type
  TIntArray = class
  private
    FItems: array of Integer;
    function GetItem(Index: Integer): Integer;
    procedure SetItem(Index: Integer; Value: Integer);
  public
    // Single-index property
    property Items[Index: Integer]: Integer read GetItem write SetItem;
  end;
```

Multi-index properties are also supported:

```pascal
type
  TGrid = class
  private
    function GetCell(Row, Col: Integer): Integer;
    procedure SetCell(Row, Col: Integer; Value: Integer);
  public
    // Multi-index property
    property Cells[Row, Col: Integer]: Integer read GetCell write SetCell;
  end;
```

### Default Properties

If an indexed property is marked with the `default;` directive, it becomes the **default property** of the class. This allows you to index the class instance directly, omitting the property name entirely.

- A class can have at most one default property.
- The default property must be an indexed property.

```pascal
type
  TList = class
  private
    FItems: array of string;
    function GetItem(Index: Integer): string;
    procedure SetItem(Index: Integer; const Value: string);
  public
    property Items[Index: Integer]: string read GetItem write SetItem; default;
  end;
...
var
  L: TList;
begin
  L := TList.Create;
  L[0] := 'hello';       { equivalent to L.Items[0] := 'hello' }
  writeln(L[0]);         { equivalent to writeln(L.Items[0]) }
end;
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

PXX supports two interface models, selected with the `{$interfaces …}`
directive. The default is **COM**, matching FPC's and Delphi's default.

| Model | Directive | Lifetime | Implementing class |
| --- | --- | --- | --- |
| COM (default) | `{$interfaces com}` | Reference-counted (ARC): the compiler inserts `_AddRef`/`_Release` at assignment, parameter passing, results, and scope exit. | Inherit `TInterfacedObject`, which supplies `QueryInterface`/`_AddRef`/`_Release`. |
| CORBA | `{$interfaces corba}` | Unmanaged: no refcounting; you `Free` the underlying instance yourself. | Any class — no `QueryInterface` needed. |

Both models share the runtime representation and the same casting rules:

- **Fat pointers**: an interface value is a two-word fat pointer — a pointer to
  the interface method table (IMT), and a pointer to the underlying instance.
- **Interface inheritance**: an interface may inherit another; an implementing
  class must satisfy the derived interface and all its ancestors.
- **Implicit coercion**: a class instance assigns directly to an interface
  variable it implements, or passes to a parameter of that interface type.
- **Checked casting & type checks**: `obj is IFoo` tests implementation;
  `obj as IFoo` casts (a failed cast traps at runtime). Interface values compare
  with `=`/`<>`, including against `nil`. Interface-to-class casting is not
  supported.

### COM interfaces (default) — reference counted

Under the default COM model, an interface variable owns a reference: the
compiler retains and releases it automatically, and the object is destroyed when
the last reference goes away. Implement the interface on a class descending from
`TInterfacedObject`. The following compiles and runs on the pinned compiler:

```pascal
program interfaces_com_demo;

type
  IReadable = interface
    function ReadStr: string;
  end;

  // Interface inheritance
  IDocument = interface(IReadable)
    function GetTitle: string;
  end;

  // TInterfacedObject supplies QueryInterface / _AddRef / _Release
  TDocument = class(TInterfacedObject, IDocument)
  private
    FTitle: string;
  public
    constructor Create(const ATitle: string);
    destructor Destroy; override;
    function ReadStr: string;
    function GetTitle: string;
  end;

constructor TDocument.Create(const ATitle: string);
begin
  FTitle := ATitle;
end;

destructor TDocument.Destroy;
begin
  writeln('document released');
  inherited;
end;

function TDocument.ReadStr: string;
begin
  Result := 'body';
end;

function TDocument.GetTitle: string;
begin
  Result := FTitle;
end;

var
  doc: IDocument;
begin
  doc := TDocument.Create('PXX Manual');   { reference count = 1 }
  writeln(doc.GetTitle, ': ', doc.ReadStr);

  if doc is IReadable then
    writeln('implements IReadable');

  doc := nil;   { last reference released — the destructor runs automatically }
  writeln('done');
end.
```

Output:

```
PXX Manual: body
implements IReadable
document released
```

Note that no `Free` call is needed — assigning `nil` (or the variable going out
of scope) drops the reference count to zero and destroys the object.

### CORBA interfaces (opt-in) — manual lifetime

`{$interfaces corba}` selects the lightweight, unmanaged model: no `_AddRef`/
`_Release`, no `QueryInterface` requirement, and any class can implement an
interface. You manage the underlying instance's lifetime yourself. This matches
FPC's `{$interfaces corba}` mode:

```pascal
program interfaces_corba_demo;
{$interfaces corba}

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

  // A plain class — no TInterfacedObject needed under CORBA
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

  writer := doc;
  writer.WriteStr('CORBA-style interfaces are lightweight.');

  reader := doc as IReadable;
  writeln(doc.GetTitle, ': ', reader.ReadStr);

  if doc is IDocument then
    writeln('doc implements IDocument');

  doc.Free;   { manual cleanup — no reference counting under CORBA }
end.
```

Output:

```
PXX Design Manual: CORBA-style interfaces are lightweight.
doc implements IDocument
```

## Metaclasses (`class of`)

A **metaclass** type — `class of TSomeClass` — holds a class reference rather
than an instance. A metaclass variable can call the class's `class` methods, and
`virtual` class methods dispatch to the runtime class it holds. This is the basis
for factory patterns and class registries.

```pascal
program metaclass_demo;

type
  TShape = class
    class function Name: string; virtual;
  end;

  TShapeClass = class of TShape;

  TCircle = class(TShape)
    class function Name: string; override;
  end;

class function TShape.Name: string;
begin
  Result := 'shape';
end;

class function TCircle.Name: string;
begin
  Result := 'circle';
end;

var
  k: TShapeClass;
begin
  k := TCircle;
  writeln(k.Name);   { virtual class method dispatches through the metaclass }
end.
```

Output:

```
circle
```

## Class properties and class vars

A `class var` field is shared by all instances (one storage slot per class, not
per object). A `class property` exposes it through the class name. Accessors may
be `class` methods or the `class var` itself.

```pascal
program class_property_demo;

type
  TCounter = class
  private
    class var FTotal: Integer;
    class function GetTotal: Integer;
  public
    class property Total: Integer read GetTotal;
    constructor Create;
  end;

class function TCounter.GetTotal: Integer;
begin
  Result := FTotal;
end;

constructor TCounter.Create;
begin
  Inc(FTotal);
end;

var
  a, b: TCounter;
begin
  a := TCounter.Create;
  b := TCounter.Create;
  writeln('instances created: ', TCounter.Total);   { read through the class }
  a.Free;
  b.Free;
end.
```

Output:

```
instances created: 2
```

## Next

- [Types](./types.md)
- [Back to the language reference](./index.md)
