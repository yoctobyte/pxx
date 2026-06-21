# Nested routines (procedures/functions inside a routine or method)

- **Type:** feature (compiler / parser + closure conversion)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** next `examples/adventure` blocker after `feature-default-standard-units`
  (done). NOT a bug — nested routines were simply never implemented (not in plain
  procedures, not in methods). Mainly a variable-scoping problem if done right
  (Approach B below).

## Symptom

If `examples/adventure/engine.pas` explicitly imports `textfile`, the demo gets
past file I/O and set iteration, then fails in `TGame.LoadWorld`:

```pascal
procedure TGame.LoadWorld(const path: AnsiString);
var
  f: Text; line, key, val, h, t: AnsiString;
  kind, ridx, midx, nidx, n: Integer; pendingQ: AnsiString;

  procedure AddExit(roomI: Integer; hidden: Boolean; const spec: AnsiString);
  var dd: TDirection; a, b, c: AnsiString; k: Integer;
  begin
    ...
  end;

begin
  ...
end;
```

```text
Expected: begin, but got: procedure (Kind: 10, Line: 604)
pascal26:604: error: unexpected token ()
```

The nested helper captures method state (`Rooms`) and local values.

## Current state (examined 2026-06-21)

NO nested-routine machinery exists anywhere — no static link, no display, no
closure/capture (grep for nested/static.link/display/capture finds only
unrelated dyn-array/include/C-struct hits). Two gaps:

- **Parse:** the routine-body decl loop accepts only `var/const/type`
  (`parser.inc:9659` for plain routines, `:10453` for the method path). A
  `procedure`/`function` token there falls through → `Expected: begin`. This is
  the visible adventure error at `engine.pas:604`.
- **Capture:** adventure's `AddExit` reads `Rooms` (a field via `Self`) and
  enclosing locals → real capture, not just parse-acceptance.

Architecture facts that pick the approach:
- Procs are a **flat global list**; each `Procs[].BodyAddr` is a code offset,
  bodies appended sequentially. A nested body can just become another top-level
  proc — no structural blocker.
- Locals are `rbp`-relative `Syms[].Offset`, **one frame per proc**.
- Scope is `SymCount` save/restore (already block-structured).

## Approaches considered

- **A — static link / display (classic Pascal).** Hidden arg = parent frame
  pointer; nested body derefs it (walking N links) for uplevel locals. Most
  general (escaping closures, recursion), but every var load/store/lea in a
  nested body must branch own-frame vs uplevel and walk links → touches
  **var-addressing codegen in all 5 backends**. REJECTED: that cross-target ABI
  depth is exactly the expensive kind, and PXX does not need escaping closures
  (the Delphi anon-method idiom is off-plan).
- **B — closure conversion / lambda-lifting. CHOSEN.** Rewrite each nested
  routine into a top-level proc that takes its captured variables as **by-ref
  params** plus `Self` (when a method) as a param; rewrite call sites to pass
  `@capturedvar` / `Self`. Reuses the by-ref param ABI that already works
  byte-identical on all 5 targets → **zero codegen/frame change, stays a
  front-end/AST problem.** By-ref capture mutates correctly for free.
- **C — flatten-only, no capture.** Parse-accept, emit as sibling proc, allow
  only own-locals + globals, hard diagnostic on any enclosing-local/`Self` use.
  Cheap de-risking slice; does NOT unblock adventure on its own.

Performance note to leave in code/docs: lambda-lifted nested routines are **not
speed-optimized** — every captured variable becomes a by-ref param (an extra
pointer arg + a deref per access), and `Self`-field access goes through the
passed `Self`. Correct and fully functional, but a hot nested loop pays indirection
the parent's direct frame access would not. Acceptable; revisit only if profiling
shows a real hotspot.

## Plan — slice C then B, capped at 1 nesting level first (adventure is proc-in-method)

### Slice 1 (C) — parse acceptance + flatten. ~½ day.
- Accept `procedure`/`function` declarations in the routine-body decl section at
  BOTH `parser.inc:9659` (plain routines) and `:10453` (methods), after the
  var/const/type sections and before `begin`. There may be more body-decl loops
  (init sections etc.) — grep `while CurTok.Kind in [tkVar, tkConst, tkType]`.
- Parse each nested routine like a normal routine, but emit its body as a fresh
  top-level entry in `Procs[]` (its own frame, own `BodyAddr`). Give it a
  mangled unique name (e.g. `ParentName$NestedName`) so it can't collide.
- For Slice 1, RESTRICT: if the nested body references an enclosing local or
  `Self`, raise a clear error ("nested routine capture not yet supported — Slice
  2"). Own locals + params + globals + module-level work.
- Regression: a plain routine and a method, each with a nested helper that uses
  only its own locals + globals.

### Slice 2 (B) — closure conversion. ~2–4 days. The real work.
- **Free-variable analysis:** walk the nested routine's AST and classify every
  identifier reference as: own-local / own-param / **enclosing-local** /
  **enclosing-param** / `Self`-field (implicit or explicit) / global / proc-call.
  The "enclosing-*" and `Self`-field cases are the captures. Needs the enclosing
  scope's symbol set visible at the rewrite point (the nested routine is parsed
  while the parent's syms are still in scope — capture that boundary).
- **Rewrite the nested signature:** append one hidden by-ref param per captured
  enclosing variable, plus a `Self` param if any `Self`/field capture occurred.
  Deterministic param order (source order of first capture) so emission stays
  byte-identical.
- **Rewrite the body refs:** each captured ident → the new by-ref param (deref);
  each `Self`-field → field access through the passed `Self`. Reuse the existing
  by-ref-param load/store and implicit-Self lowering — do NOT add new codegen.
- **Rewrite call sites:** every call to the nested routine inside the parent gets
  the extra actual args appended: `@capturedvar` for each capture, `Self` for the
  Self param. Captured-var address is just `IR_LEA`/`IR_SLOTADDR` of the parent
  local (same as a `var` argument today).
- **Cap nesting at 1 level** initially. A capture-of-a-capture (proc in proc in
  proc, where the innermost uses a grandparent local) needs the middle routine to
  re-thread the param down — defer with a clear diagnostic; adventure is 1 level.
- `@nested` (address-of a nested routine) and passing a nested routine as a
  proc-typed argument: defer with a diagnostic — the by-ref captures are only
  valid while the parent frame is live, so an escaping nested routine is unsound
  under B. (This is the deliberate limitation vs Approach A; documented, off-plan.)

## Acceptance

- Slice 1: a plain routine and a method, each with a nested routine using only
  own locals/globals, compile and run; capture attempts give the clear
  diagnostic.
- Slice 2: a method-local nested routine that reads/writes a field through
  implicit `Self` AND reads/writes an enclosing local compiles and runs;
  `TGame.LoadWorld` gets past `AddExit`; `examples/adventure` advances past
  `engine.pas:604`.
- `make test` green; self-host fixedpoint byte-identical (a codegen/emit-shaped
  change → expect a 1-gen reseed, fix with `make bootstrap`; see
  feedback_codegen_reseed_not_nondeterminism in agent memory).
- All 5 targets compile a nested-routine test (cross output-equality; the by-ref
  ABI is already at parity so no per-target codegen is expected).

## Log

- 2026-06-21 - Opened from the adventure compile path. With explicit
  `uses textfile`, current compiler reaches this parser error at
  `engine.pas:604`.
- 2026-06-21 - Reframed bug → feature after review with user. Confirmed nested
  routines are entirely unimplemented (no capture machinery exists). Decided
  Approach B (closure conversion / lambda-lifting via by-ref params + Self param)
  over A (static link) to keep it front-end-only and avoid 5-backend codegen
  depth; C as a cheap de-risking first slice. Performance note: lifted nested
  routines are not speed-optimized (indirection per captured access).
