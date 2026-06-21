# Local typed constants (initialized const inside a routine)

- **Type:** feature (compiler — declaration parse + init)
- **Status:** done
- **Owner:** Track A
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

## Resolution (2026-06-21, Track A)

Routine-local typed constants now lower as routine-scoped read-only initialized
locals: `ParseConstSection` allocates storage via the existing `AllocArray`/
`AllocVar` (scope-aware from `CurProc`) and, when `CurProc >= 0`, records the
element/scalar initializers into a new per-routine `LocalInit*` list (defs.inc)
instead of the global `PendingInit` list. `CompilePendingLocalInits` emits those
as assignment AST in the routine prologue — after managed-local zero-init, before
the body — so the stack table is re-initialized on each call. Wired at both
routine-body sites (`ParseSubroutine` and the unit `__init_*` section); reset at
routine entry.

Also fixed a pre-existing gap that blocked the chess shape: `ConstEval` rejected
a single-char string literal (`'a'`, lexed as `tkString`); now a length-1
`tkString` evaluates to its character code, so `array[..] of Char = ('.', 'P',
...)` initializers work (globals too).

- Commits: parser.inc + defs.inc + Makefile + test.
- Gate: `make test` green; default + `--threadsafe` self-host byte-identical.
- Test: `test/test_local_typed_const.pas` (array Integer + array Char + scalar +
  per-call re-init); output `100 a b c 42 100` equal on x86-64 / i386 / aarch64 /
  arm32 (QEMU); compiles on esp riscv32 + xtensa.
- chess: now parses past `chess.pas:846`; next blocker is a Track-B PAL wiring
  gap — see `chess-pal-getdents-link` (backlog).
- Follow-up (punted): string/float/record local typed-const initializers.
