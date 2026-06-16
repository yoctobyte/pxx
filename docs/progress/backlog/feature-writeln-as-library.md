# write/writeln as a library function (via `array of const` + variadic sugar)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-16

## Motivation

The builtin `write`/`writeln` are special-cased in codegen (`IR_WRITE` /
`IR_WRITELN`) and are not fully FPC-compatible: no file handles, partial format
support, fixed stdout. Now that `array of const` (TVarRec) is a stable,
self-hosted feature — the compiler's own asm-text emitter consumes
`items[i].VType` on all targets, element tags (incl. `vtExtended` for floats)
live in `compiler/builtin/builtinheap.pas` — `writeln` can be expressed as an
ordinary **library** routine taking `array of const`, with a little syntactic
sugar to keep the familiar call shape.

The sugar is the real win: it makes ANY user-defined variadic routine ergonomic
(`Log(...)`, `Format(...)`, `Assert(...)`), not just writeln.

**Do NOT replace the builtin writeln.** The library version must coexist and be
opt-in until it is proven byte-identical; `compiler.pas` self-hosts on the builtin
(871-proc fixedpoint) and must not regress.

## The three pieces (dependency order)

### 1. Variadic bracket-elision (useful standalone)

At a call `f(a, b, c)` where `f` resolves to a routine whose last (or only)
parameter is `array of const`, and the arguments are not already a single
`[...]` literal, auto-wrap them into the TVarRec literal: `f([a, b, c])`. The
call-arg builder already constructs `AN_VARREC_ARRAY`; do the wrap in that one
place.

- **Ambiguity rule (non-strict, predictable):** the variadic form is a
  *fallback*. Only elide brackets when no non-variadic overload matches the given
  argument list; prefer an exact non-variadic match. This avoids surprises when a
  `writeln(s: string)` overload also exists.
- **Don't double-wrap** an already-bracketed call.
- This alone lets users write `Log('x=', x, ' y=', y)` against
  `procedure Log(const a: array of const)`.

### 2. `expr:w:p` formatting via a format element

Add a `vtFormatted` element tag (in `builtinheap.pas`) carrying the value, its
underlying type, a width, and a precision. The parser — **only inside a loosened
variadic argument list** — rewrites `arg : w [ : p ]` into a `vtFormatted`
element (the `:` is unambiguous in that position; it is where FPC parses
width/precision too). The library `writeln` reads the tag and formats. Floats
already box as `vtExtended`, so `x:0:2` on a Double works.

### 3. File handles

`writeln(f, ...)` where the first argument is a file/text value routes output to
its file descriptor instead of stdout. Phase it:

- First: stdout / stderr (a `TextFile`-typed first arg resolving to fd 1/2).
- Later: real file I/O — `TextFile`, `AssignFile`/`Reset`/`Rewrite`/`CloseFile`,
  buffering. This is where the current builtin is genuinely incomplete.

## Constraints / gotchas

- **Coexistence + opt-in:** keep the builtin as default; gate the library version
  behind a unit or define. No default flip until byte-identical parity is proven
  and `make` / `make cross-bootstrap` stay green.
- **Exact output parity:** newline/flush/line-buffering, integer and float
  formatting digits, boolean rendering (PXX currently prints `1`, FPC `TRUE` —
  decide and match). Validate against `test_conformance_*` and the cross suites.
- **Performance:** each library `writeln` boxes a TVarRec vector (heap alloc).
  Acceptable for normal use; note it for hot logging paths; consider a fast path
  for the trivial single-scalar case if it matters.
- **Managed strings:** the library `writeln` pulls in `builtinheap` (array of
  const already allocates) — already true for array-of-const programs.

## Suggested phasing

1. Variadic bracket-elision (generic; ship + test with a user `Log`).
2. `vtFormatted` tag + parser `:w:p` rewrite in variadic arg lists.
3. Library `write`/`writeln` to stdout/stderr in a unit, behind a define; prove
   output parity on the conformance + cross suites.
4. File-handle forms (`TextFile`, Assign/Reset/Rewrite).
5. Much later: consider making the library version the default, only after a
   byte-identical self-host + cross-bootstrap proof.

## Notes

- Element tags today: vtInteger 0, vtBoolean 1, vtChar 2, vtExtended 3,
  vtPointer 5, vtAnsiString 11, vtInt64 16 (`builtin/builtinheap.pas`). Add
  vtFormatted alongside.
- Related: the bracket-elision sugar is independently valuable — could land and be
  used for user variadics well before any writeln rewrite.
