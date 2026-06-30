# Implicit (sloppy) local variables behind a switch — `{$IMPLICITVARS ON}` / `--auto-locals`

- **Type:** feature (language / parser) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Origin:** the original `--auto-locals` idea
  (feature-implicit-identifier-binding-strictness-switch, "the originally-imagined
  feature"), correctly scoped after a design pass as an **opt-in, non-standard**
  layer. The typed/standard layer is [[feature-inline-loop-var-rio]].

## Idea

Under an explicit opt-in switch, an assignment to a **previously-undeclared** name
creates an inferred local (no `var`, no type):

```pascal
{$IMPLICITVARS ON}      { or  pxx --auto-locals  }
begin
  i := 0;               { implicit local, inferred Integer }
  s := 'abc';           { implicit local, inferred AnsiString }
  for i := 0 to 9 do ...
end;
```

This is "sloppy mode" — Python/BASIC ergonomics in Pascal. pxx's **Nil-Python and
BASIC frontends already do exactly this**, via the same `tyAuto` (defs.inc:540)
inference the inline-`var` path uses, so the machinery exists.

## Why / why behind a switch

- **Why:** eliminate boilerplate for scratch variables; ease porting Python/BASIC
  and quick scripts.
- **Why opt-in (NEVER default):** it masks typos — `cont := 0` silently makes a new
  variable instead of erroring on the misspelling of `count`. Pascal-the-language
  is declare-before-use; this is a deliberate departure.

## Behaviour

- **Default (off):** an undeclared `i := 0` is an **error** (today's behaviour —
  the decl-order gating fix, feature-implicit-identifier-binding-strictness-switch,
  already does this correctly). Unchanged.
- **`{$IMPLICITVARS ON}` / `--auto-locals`:** assignment to an undeclared name
  declares a `tyAuto` routine-local, type inferred from the RHS (reuse the
  inline-`var := expr` resolve at parser.inc ~7550). Emit a **warning**
  (`implicit variable 'i'`) so it is visible (suppressible).
- **`--strict` / `{$DECLORDER ON}` strict family:** force it off (hard error) even
  if requested, so strict builds stay declare-before-use.

## Implementation notes

- The hook is the lvalue-resolution failure in the assignment-statement path:
  where `FindSym(name) < 0` for the LHS today raises "undefined variable", under
  the switch instead `AllocVar(name, tyAuto)` (routine-local) and continue, then
  let the RHS inference fill the type — the exact path the inline-`var` statement
  already uses (parser.inc ~7512/7550). Guard with the new switch global +
  `EnableAutoVar`.
- A `tyAuto` local that is read before any assignment must still error
  (`use of auto variable before type is inferred`, parser.inc ~4223 already
  exists) — so a bare read of an undeclared name stays an error even in sloppy
  mode; only assignment creates one.

## Acceptance

- Off by default: undeclared `i := 0` errors (unchanged). With `--auto-locals` /
  `{$IMPLICITVARS ON}`: it declares + infers, runs, and warns. `--strict` forces
  the error regardless. Self-host byte-identical (switch off in the self-build).
  Tests: off-errors, on-infers-and-warns, strict-overrides, read-before-assign
  still errors.
