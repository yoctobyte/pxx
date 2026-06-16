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

Interfaces are **not** implemented (deferred until a concrete target needs them).

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
