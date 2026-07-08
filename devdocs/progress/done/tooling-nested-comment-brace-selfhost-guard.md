---
prio: 40  # auto
---

# Nested-comment brace hazard in compiler source — investigation + lint guard

- **Type:** tooling / lexer investigation. Track A (compiler source discipline).
- **Filed:** 2026-07-08 (post-fix). Trigger: a stray `{` in a `{ }` comment on a
  new C-frontend function crashed self-host with `unexpected character` at a
  bogus past-EOF line, costing a build cycle.

## Question raised
"Multiple issues with nested comments vs a character in a string constant — what
is the grosso-modo consensus, for BOTH the Pascal and the C frontend?" Guiding
principle: **be compliant with de-facto standards.**

## Finding — already de-facto compliant on every axis (no lexer change)
Verified empirically against `pascal26` (both frontends, both roles: compiling
programs AND self-lexing):

- **Literals vs comments are mutually inert** (universal rule): whoever opens
  first wins; the other's delimiters are plain data inside. So `'{'`, `"/* */"`,
  `"//"`, and a `'`/`"`/`{` inside a comment all lex correctly. ✅
- **Pascal `{ }` nests; `{$mode delphi}` turns it off** — matches **FPC 3.2.2**
  (fpc/objfpc default on; delphi off). `{$NESTEDCOMMENTS on/off}` overrides.
  (`lexer.inc:642`, NestedComments=True default.) ✅
- **C `/* */` does NOT nest** — matches the **C standard / gcc / clang**. ✅
- Mixed-delimiter is inertness, not nesting: `{ (* *) }` and `(* { } *)` always
  work; inside a `{ }` comment, `//`, `(* *)`, and string quotes are all inert. ✅

Conclusion: **nothing to change in either lexer.** The behaviour is the de-facto
standard. Keeping `{ }` nesting ON is required (the compiler is FPC-seeded and
compiles FPC-mode code); `{$mode delphi}` already flips it off per-unit.

## The one real fragility — self-inflicted, in the compiler's OWN source
Under `{$nestedcomments on}`, a **lone** `{` or `}` in the prose of a `{ ... }`
comment (e.g. the phrase "a paren followed by `{`") shifts the nesting counter,
so the comment closes at the wrong `}` — usually running to EOF — and self-host
dies as `unexpected character` at a fake line number. **Balanced** interior
braces (`({...})`) are safe under nesting. This is a known FPC authoring gotcha;
FPC's own source avoids it the same way.

De-facto convention (adopted here): **use `(* *)` or `//` for brace-containing
comment prose in `compiler/*.inc`, or keep braces balanced.**

## Delivered
`tools/lint_comment_braces.py` (commit **48c411d6**) — emulates the nesting lexer
over `compiler/*.inc` + `*.pas`:
- **ERROR** (default, exit 1): unterminated `{ }` comment — the exact self-host
  breaker, pinpointed at the opening `file:line:col`. **0 in the current tree.**
  Verified: fires on a reconstructed lone-brace comment; passes balanced
  `({...})`.
- **WARN** (`--strict`): any brace inside a `{ }` comment — **688 today**, mostly
  benign balanced examples that would only misparse under `{$mode delphi}`; for
  anyone wanting Delphi-portable comments.

## Remaining (decisions for the owning track, not blockers)
1. **Gate wiring** — the ERROR-level check is 0-cost and 0-false-positive today;
   worth adding to the pre-build gate (Makefile `all` prereq, or a Track T
   `testmgr` quick step) so a future lone brace fails fast with a real location
   instead of `unexpected character at 69506`. Left unwired pending a call on
   where it belongs (build vs testmgr — Track T owns `testmgr.py`).
2. **`--strict` backlog (688 warnings)** — optional cleanup only if Delphi-mode
   portability of the compiler's own comments ever matters (it does not today).
   Not recommended as busywork.

## Related
Landmine memory saved. See also the codegen-reseed note
([[feedback_codegen_reseed_not_nondeterminism]]) — the OTHER self-host failure
mode (2-step build/verify convergence, distinct from this "unexpected character")
that the reverted switch-nonblock attempt hit
([[bug-c-switch-nonblock-and-duffs-device]]).
