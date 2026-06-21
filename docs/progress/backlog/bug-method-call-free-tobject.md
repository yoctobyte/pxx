# `obj.Free` rejected — built-in TObject has no `Free` method

- **Type:** bug / feature (compiler object model — Track A)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** next `examples/chess` blocker after `feature-eof-stdin-builtin`
  (done). Chess now parses to `chess.pas:961`.

## Problem

```pascal
eng.Free;   { pascal26:961: error: unexpected token () / Expected: := }
```

A parameterless method call on a declared method works (`f.Bar;` parses), so the
gap is specific to `Free`: the built-in `TObject` (classes.pas notes "TObject is
built in") exposes no `Free` method, so `obj.Free` is parsed as a field-access
lvalue and the parser then demands `:=`.

Minimal repro:

```pascal
type TFoo = class procedure Bar; end;
...
f := TFoo.Create;
f.Bar;    { ok }
f.Free;   { error: Expected := }
```

## Direction

- Give the built-in `TObject` a `Free` method (the FPC idiom: `if Self <> nil then
  Destroy`), calling the destructor then releasing the instance heap block. PXX
  already has class instantiation + destructors + the heap; this wires the
  standard `Free` entry point.
- Track A owns the built-in TObject / object model. If TObject is instead grown in
  RTL, coordinate with Track B — but the "built in" comment suggests the compiler.
- Watch the error path: an unknown `.Method;` should not silently become an lvalue
  awaiting `:=`; a clearer "unknown method" diagnostic would help.

## Acceptance

- `obj.Free;` compiles and frees the instance (destructor runs; double/`nil` Free
  is safe).
- `examples/chess` advances past `chess.pas:961`.

## Log
- 2026-06-21 — filed (self-discovered as the next chess blocker after Eof).
