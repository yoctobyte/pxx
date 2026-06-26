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
