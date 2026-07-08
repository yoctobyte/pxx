---
prio: 45  # auto
---

# Comment diagnostics to de-facto standard: unterminated-comment error (Pascal) + -Wcomment (C)

- **Type:** feature (lexer diagnostics). Track A (shared `lexer.inc`) + Track C
  (C frontend comment scan). Owner: a-agent (2026-07-08).
- **Origin:** investigation of nested-comment vs literal lexing (see
  [[tooling-nested-comment-brace-selfhost-guard]]). Guiding principle: **be
  compliant with de-facto standards.**

## Investigation result (already compliant, except diagnostics)
Verified empirically against `pascal26` (both frontends, both roles):
- Literals shield comment delimiters and vice-versa — universal, correct. ✅
- Pascal `{ }` nests, `{$mode delphi}` off = **FPC 3.2.2**. ✅
- C `/* */` does NOT nest = **C standard / gcc / clang**. ✅
- Mixed-delimiter inertness (`{ (* *) }`, `(* { } *)`) works. ✅

The behaviour is the de-facto standard; **no lexing-semantics change**. Two
DIAGNOSTIC gaps vs the standard remain:

### 1. Pascal: unterminated comment gives a garbage cascade (PRIMARY)
Every compiler (FPC/gcc/clang) reports `unterminated comment` at the OPENING
location. `pascal26` instead cascades:
```
{ this comment never closes ...        (opened line 4)
pascal26:28: error: undefined variable (interface)   <- bogus, far away
```
This is the exact original pain (a lone brace in an `.inc` comment crashed
self-host as `unexpected character` at a past-EOF line). Fix: when a `{ }` or
`(* *)` comment scan hits EOF unclosed, emit `unterminated comment (opened at
line X, col Y)`. Makes the external lint
([[tooling-nested-comment-brace-selfhost-guard]]) redundant for the fatal case.

### 2. C: no -Wcomment (SECONDARY)
`gcc -Wall` / `clang`: `warning: "/*" within comment [-Wcomment]` when a `/*`
appears inside a block comment (a likely mistake — C comments do not nest).
`pascal26`'s C frontend is silent. Add the warning to match.

Note: a per-`{` "ignoring delimiter" warning for the PASCAL nesting case is NOT
standardized — FPC nests intentionally, so it would fire on every legitimate
nested/balanced comment (688 in-tree). Not added.

## Gate
- Track A: `make test` + self-host byte-identical.
- Track C: C tests green + conformance no-regress.
- New: a Pascal source with an unterminated `{`/`(*` comment reports
  `unterminated comment` at the open; a C `/* /* */` compiles AND warns
  `-Wcomment`; well-formed comments unaffected.

## Log
- 2026-07-08 — resolved, commit 0aa9505d.
