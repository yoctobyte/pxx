# feature: nested (local) functions and procedures

- **Type:** feature (Track A — parser, scoping, codegen) — REGRESSION
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC (also hit earlier building DNS)
- **Severity:** medium (forces every helper to top level; no scope capture)

## Root cause — REGRESSION, not unimplemented (diagnosed 2026-06-23)

This WAS implemented (lambda-lifting slices 1/2a/2b — commits c820e78, 334d679,
e299709; marked DONE 8d15c47, 2026-06-21) and then **broke** when the declaration
**pre-scan** landed the next day (dc11a9c `feat(parser): declaration pre-scan`,
2026-06-22, + 7ba91bf for units).

Mechanism of the conflict: nested routines work by token **stash + re-injection**
— `ParseNestedRoutine` rewrites the inner routine to a forward in place and
`FlushPendingNestedProcs` re-injects its stashed tokens as a top-level sibling
(parsed later by `ParseSubroutine`). The pre-scan made `ParseProgram`/`ParseUnit`
**two-pass over recorded token spans** (`DeclItemStart/End`, `TokPos := …; Next;
ParseSubroutine`). Pass1 skips bodies via `PreScanSkipRoutineBody` (which DOES
recurse over nested routines, 10180); pass2 replays each recorded span. The
re-injected nested-routine tokens vs the pass2 span replay collide — the inner
`function`/`procedure` ends up parsed by the top-level `ParseSubroutine`
(error: `expected name`, parser.inc:10270) instead of staying inside the
enclosing body's decl loop (11474 → `ParseNestedRoutine`).

Fix needs the two mechanisms reconciled (e.g. nested routines registered/handled
within the pre-scan span model, or flushing coordinated with the pass2 replay) —
deep parser interaction, self-host-risky → do live, not autonomously. The
PreScanSkipRoutineBody nested recursion already exists; the gap is pass2 + flush.

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
