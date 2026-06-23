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

### Precise mechanism (line-level, 2026-06-23)

`FlushPendingNestedProcs` (parser.inc:10076) does
`InsertTokens(TokPos-1, PendNestTok, PendNestCount); Dec(TokPos); Next;` — it
splices the stashed nested-routine tokens **into the middle** of the token stream
and returns, relying on the *caller's decl loop* to then parse the spliced
`function`/`procedure` as a sibling (the old single-pass `ParseProgram` did
exactly that).

The pre-scan pass2 (parser.inc:~13038 program, ~12479 unit) instead replays fixed
spans: `for i := 0 to DeclItemCount-1 do begin TokPos := DeclItemStart[i]; Next;
ParseSubroutine; end`. Two breakages:
1. After `ParseSubroutine(f)` returns (pass2), the spliced nested tokens sit at
   `TokPos`, but the loop overwrites `TokPos := DeclItemStart[i+1]` — the nested
   routine is **never parsed**.
2. `InsertTokens` shifts every token index after the splice point, so the
   pass1-recorded `DeclItemStart[i+1..]` now point at the **wrong tokens** →
   `ParseSubroutine` lands on a non-name token → `expected name`
   (parser.inc:10270).

Fix sketch (live): make nested-routine flushing pre-scan-compatible — e.g. APPEND
the nested tokens at end-of-stream (no mid-stream shift), record them as their own
DeclItem, and make the pass2 driver a `while i < DeclItemCount` loop (not a fixed
`for`) so appended items are parsed. Must keep the old single-pass path working
and stay self-host byte-identical. Needs full `make test`.

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
