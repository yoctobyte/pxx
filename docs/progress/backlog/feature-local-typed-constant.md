# Local typed constants (initialized const inside a routine)

- **Type:** feature (compiler — declaration parse + init)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** next `examples/chess` blocker after the Inc/Dec lvalue fix
  (e92ebd5). Sibling of `feature-typed-const-arrays` (done — globals only; that
  ticket lists "local typed consts" as out of scope).

## Problem

A typed constant declared in a routine's `const` section is rejected:

```text
pascal26:846: error: local typed constant not supported; use a const expression or a var
```

Repro (`examples/chess/chess.pas`, `PieceGlyph`):

```pascal
function PieceGlyph(const pc: TPiece): Char;
const
  W: array[pkNone..pkKing] of Char = ('.', 'P', 'N', 'B', 'R', 'Q', 'K');
  B: array[pkNone..pkKing] of Char = ('.', 'p', 'n', 'b', 'r', 'q', 'k');
begin
  ...
```

Global typed constants (incl. array initializers) already work
(`feature-typed-const-arrays`, 54d5dda) via the pending-init machinery that
allocates storage and compiles the initializer as assignments before `main
begin`. The local form hits an explicit "not supported" guard.

## Direction

- A local typed constant is effectively a routine-scoped read-only initialized
  variable. Simplest correct lowering: allocate it like a local, emit the
  element initializers in the routine prologue (once per call is acceptable; an
  optimization would hoist immutable tables to global rodata).
- Reuse the global typed-const-array initializer path where possible; the
  element list parse `( v0, v1, ... )` already exists for globals.
- Cover at least: ordinal/Char/Int64 scalar and array initializers (the chess
  lookup-table shape). String/float/record initializers can follow.

## Acceptance

- `PieceGlyph`'s `W`/`B` char-array constants compile and index correctly.
- `examples/chess` advances past `engine`/`chess.pas:846`.
- A focused test: a function-local `const T: array[0..3] of Integer = (...)`
  read back by index, output-equal on all targets.
