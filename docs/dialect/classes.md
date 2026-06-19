# Classes & RTTI

## Classes

Single-inheritance classes with:

- fields, methods, constructors/destructors;
- `virtual`/`override` dispatch through a VMT;
- properties (read/write, field- or method-backed);
- visibility sections (`private`/`protected`/`public`/`published`) — **parsed but
  not enforced**;
- `inherited`;
- `class of` metaclasses and class-reference values (e.g. passing a `TFormClass`
  to a factory).

## Interfaces (CORBA-style)

CORBA-style interfaces are implemented on all four targets (x86-64 / i386 /
aarch64 / arm32):

```pascal
type
  IFoo = interface
    function F: Integer;
  end;
  IBar = interface(IFoo)       // interface inheritance
    function B: Integer;
  end;
  TA = class(IBar)             // a class implements interface(s) in its heritage list
    function F: Integer;
    function B: Integer;
  end;
```

Supported:

- declare, implement (class heritage list), call through an interface value;
- an interface value is a fat pointer `{IMT, instance}` (2 pointer-sized words);
- class → interface assignment, and **implicit coercion** when a class is passed
  to an interface parameter or assigned to an interface `Result`;
- `obj is IFoo`, `Supports(obj, IFoo)`, and `obj as IFoo` (checked cast to an
  interface value; `nil` passes through, a bad cast traps);
- identity `=` / `<>` (compares the referenced instance) and `iface := nil`;
- **interface inheritance** `interface(IParent)` — inherited methods occupy the
  leading IMT slots, so a derived interface dispatches them and widens to its
  base; a class implementing a derived interface also satisfies every ancestor.

Not (yet) implemented — **automatic reference counting** (COM-style ARC:
`IInterface`/`TInterfacedObject`, compiler-inserted `_AddRef`/`_Release`). It is
deferred (low priority — see `feature-interface-refcounting`); the current model
is CORBA (no refcount), matching FPC `{$interfaces corba}`. GUID literals are
parsed and ignored. `implements` delegation and method-resolution clauses are out
of scope.

## Published RTTI

`published` members generate run-time type information (property tables, type
kinds). Inspect generated tables with `--dump-rtti`. The `typinfo` unit exposes
the reader side.

## `.lfm` streaming (Lazarus forms)

PXX can stream a `.lfm` form description into a live component tree via published
RTTI:

- `{$R *.lfm}` (or `{$R name}`) queues the form resource for the current unit;
- the `classes`/`lfm` RTL units provide the component/streaming machinery;
- a **stock GTK3 Lazarus helloworld compiles and runs unmodified** — see
  [`developer/gui.md`](../developer/gui.md).

RTL/LCL units live under `lib/rtl/` and `lib/lcl/` (`classes`, `collections`,
`typinfo`, `streams`, `math`, `controls`, `forms`, `stdctrls`, `dialogs`,
`graphics`, `gtk3`, …).

See [Not Implemented](../not-implemented.md) for the FPC RTL boundary: the full
FPC RTL, `SysUtils`, and the package ecosystem cannot be assumed to compile —
only the units shipped here and tested built-ins are available.
