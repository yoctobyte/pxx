# Implicit identifier binding — forward-visible globals + optional auto-local, with a strictness switch

- **Type:** feature (language / parser) — Track A
- **Status:** backlog — **core gating DONE (pin v93)**; only the smaller
  follow-ups below remain (clearer diagnostic, opt-out switch, `--auto-locals`).
  See "Resolution" at the bottom.
- **Owner:** unassigned
- **Opened:** 2026-06-30
- **Found by:** the FPC-seed bootstrap break
  ([[bug-fpc-seeded-binary-runtime-segfault]]). `ParseCSubroutine`'s inner loop
  `for j := i+1 to nparams-1` has **no local `j`**; pascal26 compiled it fine for
  weeks, FPC rejected it ("Identifier not found j / Illegal counter variable").
  NOTE: the "double-edged feature" framing below was the initial read; after
  investigation the forward-visible-global-**variable** case was confirmed a
  **bug** and fixed by default — see Resolution.

## What actually happens (mechanism, verified 2026-06-30)

Two separate behaviours, often confused:

1. **NOT auto-local.** A genuinely undeclared identifier still errors. pascal26:
   ```pascal
   program undecl; begin for zzqq := 1 to 3 do writeln(zzqq); end.
   ```
   → `error: for: undefined`. So pascal26 does **not** invent a local for an
   unknown name. (`ParseForStatementAST`: `if FindSym(...) < 0 then Error('for:
   undefined')`.)

2. **Forward-visible program globals (the real cause).** The compiler's whole-
   program declaration pre-scan ([[project_declaration_prescan_done]]) makes
   program-level `var` globals visible to *every* routine, including routines
   declared **textually above** the global's declaration. So:
   ```pascal
   program glob;
   procedure P; begin for j := 1 to 3 do writeln(j); end;  { uses j }
   var j: Integer;                                          { declared AFTER P }
   begin P; end.
   ```
   compiles and prints 1/2/3 under pascal26; FPC rejects it (declare-before-use).
   In the compiler that is exactly what happened: `j` in `ParseCSubroutine`
   (cparser.inc) silently bound the program-global scratch counter `n, i, j:
   Integer` at `compiler.pas:80` — declared just before the main `begin`, far
   below every include.

So the divergence from FPC is **forward-visible globals**, not implicit locals.

## Why it's a double-edged feature

Upside (why we like it): order-free top-down code. You write helpers first and a
shared scratch/global last; mutual visibility "just works", matching the pre-scan
philosophy already shipped for procs/types/consts.

Downside (why it bit us):
- **FPC-incompatibility.** Breaks the cold FPC seed / `make test-fpc` — FPC needs
  the global declared before the include that uses it.
- **Silent stray-name binding.** A typo or a forgotten local doesn't error — it
  binds whatever same-named global happens to exist. Here `j` grabbed a program
  global used as a loop counter in many routines.
- **Reentrancy hazard.** A *shared program-global* used as a routine's loop
  counter is unsafe if that routine (or anything it calls) re-enters while the
  loop is live. `ParseCSubroutine`'s `j` loop is currently safe only because it
  runs to completion without yielding — fragile by accident, not design.

## Proposal

Keep the lenient default (we like it). Add a **strictness switch** plus, as a
distinct opt-in, the auto-local convenience the bug suggested:

1. **`{$DECLORDER STRICT}` / `--strict-decl-order` (warn|error).** When an
   identifier resolves to a global declared *textually later* than the current
   routine, emit a warning (default in a `--pedantic`/FPC-mimic profile) or error.
   Catches the stray-bind class and flags FPC-incompatible source. The existing
   `--mimic-fpc` profile ([[project_mimic_fpc_done]]) is the natural home for the
   error form.
2. **Narrow loop-counter lint (cheap, high-value).** Warn when a `for` counter
   binds a **non-local** symbol (global or outer) — that is almost always a
   missing local and is the precise shape that broke FPC. Could ship on by default
   as a warning; near-zero false positives.
3. **Optional auto-local for an undeclared `for` counter (the wished feature).**
   Behind `{$AUTOLOCAL ON}` / `--auto-locals`: an *undeclared* `for x := ...`
   counter is implicitly declared as a routine-local `Integer` (range inferred
   from the bounds where possible). This is the Python-ish "just have a local var"
   ergonomic — but as an explicit, switchable feature, and a real local (no global
   aliasing, reentrancy-safe), not the accidental global-bind above. Default OFF
   so unknown names still error (catches typos).

## Immediate, separate cleanup (not this ticket)

The compiler's own `ParseCSubroutine` should declare a **local** `j` (trivial) so
the FPC seed builds — tracked under [[bug-fpc-seeded-binary-runtime-segfault]].
This ticket is the language design; the source fix is independent and should not
wait on it.

## Acceptance

- A documented switch controlling forward-later-global binding (off/warn/error),
  wired into the directive set + a CLI flag, with the error form active under
  `--mimic-fpc`.
- The non-local for-counter warning, with a test that triggers it and one that
  stays silent for a legitimate local counter.
- (If pursued) `--auto-locals` for undeclared for-counters, with tests showing an
  undeclared counter becomes a local Integer and that a stray non-counter name
  still errors.
- Self-host byte-identical (the compiler source itself must compile clean under
  whatever the default profile is — i.e. fix the `j` local first so STRICT can be
  the eventual default without breaking the bootstrap).

## Notes

- Adjacent prior art in-tree: declaration pre-scan
  ([[project_declaration_prescan_done]]), `--mimic-fpc`
  ([[project_mimic_fpc_done]]), and the various implicit-Self / bare-name
  resolution paths in the parser.
- User explicitly likes the lenient behaviour — the goal is to *keep* it as the
  default and make strictness opt-in, not to remove it.

## Resolution (2026-06-30, pin v93, commit 97805ea9) — core gating shipped as DEFAULT

Reframed after investigation: the forward-visible-**global-variable** case is a
**bug**, not a feature (user confirmed). It is non-reentrant and FPC-incompatible.
The fix shipped on by default; types/consts/procedures keep forward visibility.

**Mechanism (token-position gating).** Each program/unit global var records the
token index where it was declared (`SymDeclTok`, stamped only in the pre-scan, only
for `skGlobal`). While compiling a routine body, `FindSym` hides any global whose
declaration token is past the body's header token (`CurBodyHdrTok`). Token indices
are absolute into the single expanded `Tokens[]` stream, so methods, forward decls
and unit/builtin routines are handled by real source position — no
registration-order snapshots (an earlier per-proc-sequence design wrongly used a
method's class-declaration position instead of its implementation position and
hid legitimately-visible globals; the token approach has no such edge case).

Verified: rejects the stray-bind (`for j` → distant global), keeps the legitimate
"global before the impl" pattern (`test_dynarray_global_after_method` green),
still errors on truly-undeclared names. Self-host byte-identical; gate + 4 cross +
lua green. Guard `test/test_decl_order_global_error.pas`.

### Still open (smaller follow-ups, kept in backlog)
- **Clearer diagnostic — DONE (2026-06-30, commit 2526bd0a, pin v97).** Added
  `HiddenByDeclOrder(name)` (symtab.inc): True when FindSym is hiding a same-name,
  block-visible global *only* because of decl-order gating. Wired into the four
  undefined-name error sites (two ParseFactor lvalue paths, the statement lvalue
  path at parser.inc ParseLValueAST, and the for-counter) → emits "undefined
  variable — it is a global declared later, declare it before use" / "for counter
  is a global declared later — declare it before use, or add a local". Recomputed
  at each site (error path only) rather than via a fragile global flag.
  `test_decl_order_global_error` asserts the clearer text. Self-host
  byte-identical. The two below remain.
- **The switch.** Gating is hard-wired `DeclOrderStrict := True`. Expose it as
  `{$DECLORDER OFF}` / `--lax-decl-order` for anyone who wants the old lenient
  behavior, and surface the strict default in `--mimic-fpc`.
- **`--auto-locals` (the originally-imagined feature).** Undeclared `for x := ...`
  counter → implicit routine-local `Integer`. Default OFF (typos must still error).
  Independent of the gating above.
