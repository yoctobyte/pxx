# Implicit textfile import misses method-local `Text` in units

- **Type:** bug (compiler / implicit RTL import)
- **Status:** done (subsumed by `feature-default-standard-units`)
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** follow-up to `feature-textfile-keyword-io-dispatch`; current
  `examples/adventure` blocker after the textfile dispatch feature landed.

## Symptom

A simple program using the classic text-file surface now works:

```pascal
program p;
var f: Text; s: AnsiString;
begin
  Assign(f, '/tmp/x'); Rewrite(f); WriteLn(f, 'alpha'); Close(f);
  Reset(f); ReadLn(f, s); Close(f); WriteLn(s);
end.
```

But `examples/adventure` still fails in the `Engine` unit at a method-local
`Text` variable:

```pascal
procedure TGame.SaveTo(const path: AnsiString);
var f: Text; it: TItem; sp: TSpell; m: TMonster;
begin
  Assign(f, path); Rewrite(f);
```

```text
pascal26:563: error: undefined variable (Assign)
```

The same source gets past `Assign` if `engine.pas` explicitly imports
`textfile`.

## Root Cause

The implicit textfile loader scans tokens up front for a `Text` / `TextFile`
identifier immediately preceded by `:`. That catches program-level declarations
but misses at least this unit/method-local declaration shape before the unit's
implementation body is parsed. As a result `lib/rtl/textfile.pas` is not loaded
for the unit, so `Assign` and related routines remain unresolved.

## Direction

- Prefer a simpler standard-surface model over a fragile token scanner: load
  `textfile` as part of the default standard unit set (or via `System` once a
  real `System` unit exists), so `Text`/`Assign` visibility is uniform in
  programs, units, methods, and nested scopes.
- Keep the implementation in `lib/rtl/textfile.pas`; do not move textfile into
  `compiler/builtin`.
- Preserve code-size and target safety: default-loaded standard units must not
  emit unused routines or drag platform-specific backend code into programs that
  do not use file I/O. `textfile` should remain parse-safe on all targets, with
  PAL calls inside referenced routines only and no required initialization.
- If default-loading `textfile` makes trivial programs larger, file a follow-up
  for routine-level dead-code emission / lazy standard-unit sections before
  broadening the implicit standard surface further.
- Add a regression test with a unit containing a method-local `var f: Text`.

## Acceptance

- A unit method with local `var f: Text` can call `Assign`/`Rewrite`/
  `WriteLn(f, ...)` without explicit `uses textfile`.
- Existing simple-program implicit textfile and explicit `uses textfile` tests
  still pass.
- `examples/adventure` gets past `engine.pas:563` without adding an explicit
  `uses textfile` workaround.

## Log

- 2026-06-21 - Opened after `feature-textfile-keyword-io-dispatch` landed.
  Rebuilding `compiler/pascal26` confirmed a simple implicit `Text` program
  works, while adventure still fails at method-local `Text` in the `Engine` unit.
- 2026-06-21 - Design direction updated after review: default-load `textfile`
  with the standard surface rather than chasing every token-scan edge. Baseline
  size check before that change: `test/hello.pas` compiles to 29,086 bytes with
  both pinned v26 and rebuilt live `compiler/pascal26`; use this as a guard when
  default-loading textfile.
- 2026-06-21 - DONE via `feature-default-standard-units` (commit d5c7498). The
  token scan is gone; `textfile` is default-loaded uniformly for programs and
  units, so unit method-local `var f: Text` resolves Assign/Rewrite/WriteLn with
  no `uses textfile`/`-Fu`. `examples/adventure` clears engine.pas:563 (now
  stops at :604, the separate `bug-nested-local-procedure-in-method`). See that
  ticket for the full design + the two latent bugs the change surfaced.
