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
- 2026-06-21 — DONE. Built-in `obj.Free` desugars to the nil-guarded FPC idiom
  `if obj <> nil then begin [obj.Destroy;] FreeMem(obj); obj := nil end`
  (`GenMakeFreeObject` in parser.inc; statement-parser intercepts plain
  `obj.Free;`/`obj.Free end` on a non-record class instance with no user `Free`
  method). Destroy is dispatched (virtual when declared) only when the class or an
  ancestor has one; nil-ing the var makes a second Free a safe no-op. Verified:
  double-free + virtual-destructor repro runs correctly; `examples/chess`
  compiles fully (past :961) and runs. `make test` green — self-host fixedpoint
  byte-identical, threadsafe byte-identical, asm-emit all OK.
  Limitation: only a plain `obj.Free` where `obj` is a simple class-instance var
  is intercepted (covers chess + the repro); `arr[i].Free` / `rec.f.Free` still
  need a user `Free` method.
