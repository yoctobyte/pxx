# Some intrinsics are hard-reserved keyword tokens, blocking their use as identifiers (FPC allows it)

- **Type:** bug (lexer / parser — FPC compatibility) — Track A
- **Status:** backlog
- **Opened:** 2026-07-02 (found sweeping for siblings of the Str/New/Dispose/
  ReallocMem/SetLength/Include/Exclude variable-name collision fixed this
  session — see [[feedback_sweep_sibling_dispatch_branches]])

## Symptom

Real FPC treats built-in routine names as ordinary, non-reserved identifiers —
they can be shadowed by a local variable, parameter, or field of the same name
(only a genuine keyword like `begin`/`var`/`goto` cannot). `Str`/`New`/
`Dispose`/`ReallocMem`/`SetLength`/`Include`/`Exclude` now work the same way in
pxx (this session's fix), but a wider set does **not** — they lex as their own
dedicated hard keyword token (not a plain `tkIdent`), so they can't even be
*declared* as a variable name:

```pascal
var length: Integer;   { -> "Expected: begin, but got: length" at the var section itself }
```

Confirmed broken this way (compiles fine in real FPC as a plain identifier):
`Length`, `Chr`, `Ord`, `Low`, `High`, `Inc`, `Dec`, `Exit`, `Halt`, `Break`,
`Continue`, `FreeMem`, `GetMem`. (Checked; NOT affected — already fine as
identifiers: `Assigned`, `Random`, `Trunc`, `Round`, `Abs`, `Sqr`, `Sqrt`,
`WriteStr`, `ReadStr`, `Move`, `FillChar`, `Concat`, `Pos`, `UpCase`,
`LowerCase`, `Succ`, plus the 7 fixed this session.)

`goto` and `inherited` are *correctly* excluded from this list — real FPC also
hard-reserves those two (confirmed: `var goto: Integer;` is a syntax error in
FPC too), so pxx matching that behavior is not a bug.

## Why this is a bigger fix than the Str/New/Dispose/etc. one

That fix (this session, pin v143/v144) was cheap because those names were
already **soft keywords**: they lex as plain `tkIdent`, and `ParseStatementAST`
dispatches on the identifier's *text* via `CaseEqual(name, 'Str')` — so the fix
was just adding a `(FindProc(name) < 0) and (Tokens[TokPos].Kind = tkLParen)`
lookahead guard to each dispatch branch, matching a pattern (Insert/Delete)
that already existed elsewhere in the same function.

`Length`/`Chr`/`Ord`/`Low`/`High`/`Inc`/`Dec`/`Exit`/`Halt`/`Break`/`Continue`/
`FreeMem`/`GetMem` are **hard keywords** — the lexer assigns each its own
distinct token kind (e.g. `tklength`, `tkChr`, `tkOrd`...), and every call site
across the parser that recognizes these forms switches on `CurTok.Kind`, not on
an identifier string. Turning them into soft keywords would mean:

- The lexer would need to keep emitting `tkIdent` for these names (or a
  variant that carries both the ident text and "was this the identifier that
  spells a builtin" info), rather than a dedicated token kind.
- Every one of the (likely dozens of) places elsewhere in the parser that
  currently does `case CurTok.Kind of ... tklength: ...` or `if CurTok.Kind =
  tkOrd then ...` (`ParseFactor`, `ParseStatementAST`, possibly type-checking
  helpers) would need the same `CaseEqual(name, 'Length') and (FindSym(name) <
  0) and (FindProc(name) < 0) and (next token indicates a call, not a plain
  read)` treatment Str/New/etc. just got — for **13 names**, each touching
  more call sites than the 7 already fixed (these are far more heavily used
  than `Str`/`Insert`/`Delete`, since `Length`/`Ord`/`Inc`/`Dec`/`Exit`/`Halt`
  are among the most common operations in the entire language).
- Real regression risk: these are hot, foundational parser paths exercised by
  nearly every test program and by the compiler's own self-host build. A
  subtle mistake in loosening any one of these token checks could silently
  break ordinary use of the intrinsic itself, not just the new identifier
  case — a much higher blast radius than the previous fix's isolated
  `ParseStatementAST` branches.

## Scope estimate

Wide (13 names × however many call sites each token kind appears at, likely
dozens total across lexer.inc/parser.inc), touching hot/foundational code with
real regression risk to the intrinsics themselves — squarely "big, needs
discussion" rather than a same-night follow-up to the Str/New/Dispose fix.
Recommend: pick ONE name first (probably `Length`, the most plausible
real-world variable name of the thirteen) as a pilot to find the full set of
call sites and confirm the soft-keyword conversion pattern actually
generalizes cleanly, before doing the rest.

## Acceptance

- `var length, ord, inc, dec, exit, halt, break, continue, chr, low, high,
  freemem, getmem: <type>;` all compile and behave as ordinary variables
  (declare/assign/read), matching FPC.
- The intrinsic forms (`Length(x)`, `Ord(e)`, `Inc(x)`, `Halt`, `Chr(n)`, ...)
  are completely unaffected when the name is not shadowed by a local/global/
  param/field.
- Regression tests for each name; self-host byte-identical; full cross suite
  green (this is foundational-enough to warrant the full cross-target run,
  not just host).

## Progress — 2026-07-02, pilot landed: `Length` converted (v137)

The recommended pilot is in. Turned out much smaller than the wide estimate:
`tkLength` had exactly TWO token-consuming sites — the lexer production and
one ParseFactor case (everything else uses `-Ord(tkLength)` as an intrinsic
CALL id, which is untouched — the enum member stays). Conversion shape:

1. lexer.inc: drop the `'length' -> tkLength` production (comment left in
   place); the name lexes as a plain tkIdent.
2. ParseFactor ident dispatch: the old tkLength body moved next to Succ/Pred
   with the standard soft-intrinsic guard —
   `CaseEqual(name,'Length') and (procIdx < 0) and (FindSym(name) < 0) and
   (next = '(')`. The `FindSym` guard is REQUIRED for FPC parity: verified
   against real FPC 3.2.2 that a variable named `length` in scope shadows the
   intrinsic and makes `Length(s)` a compile error — without the guard pxx
   silently kept the intrinsic (divergence caught in testing).
3. IsDeclNameTok: dead tkLength entry removed.

Bonus: `LENGTH(...)` (any casing) now works — the old lexer production only
matched `length`/`Length` exactly, so `LENGTH` was already a broken ident.

Gate: test/test_soft_keyword_length.pas (9 cases — var/param/field/local
shadow declarations, literal + static-array folds, casing, r-value; output
byte-matched vs FPC) in make test; full suite green; self-host byte-identical.

Remaining 12 (same recipe, per-name site analysis needed): value-context ones
(`Chr`, `Ord`, `Low`, `High`) mirror Length; statement-context ones (`Inc`,
`Dec`, `Exit`, `Halt`, `Break`, `Continue`, plus `GetMem`/`FreeMem`) also
dispatch in ParseStatementAST and need the statement-side ident path.
