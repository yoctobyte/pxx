# feature: nested (local) functions and procedures

- **Type:** feature (Track A — parser, scoping, codegen)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC (also hit earlier building DNS)
- **Severity:** medium (forces every helper to top level; no scope capture)

## Gap

A function/procedure declared inside another routine is rejected at parse:

```pascal
procedure outer;
  procedure inner;          { error: unexpected token  (at 'procedure') }
  begin writeln('in'); end;
begin inner; end;
```

Same for nested functions, with or without access to the enclosing scope:

```pascal
function f(n: integer): integer;
  function g(m: integer): integer; begin g := m * 2; end;
begin f := g(n) + 1; end;          { error: unexpected token }
```

Control — two top-level functions compile and run (`f` calling `g` → 11):

```pascal
function g(m: integer): integer; begin g := m * 2; end;
function f(n: integer): integer; begin f := g(n) + 1; end;
begin writeln(f(5)); end.          { prints 11 }
```

## Expected

Support nested routine declarations (FPC does), including reading the enclosing
routine's params/locals (lexical scope). Full closure capture (taking the
address of a nested routine that escapes) can be a later phase; the common case
is a local helper called synchronously within its parent.

## Track B impact

Library code must hoist every local helper to unit scope and thread state
through parameters/globals instead of closing over it. Seen in the DNS wire
builder (a label-writer helper had to become a top-level routine) and elsewhere.
No workaround beyond hoisting; this removes that.

## Repro

`tools/fpc_diff_probe.sh` (the `nested-fn` / `nested-proc` probes).
