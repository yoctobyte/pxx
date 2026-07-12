---
prio: 65  # blocks BOTH the ZenGL ladder and the whole Synapse compile (jedi.inc)
---

# {$...} directives are processed inside (* ... *) comments

- **Type:** bug (Pascal frontend — lexer/comment handling) — **Track P**
  (edits the shared `lexer.inc`, so A's gate + no-concurrent-edit rule)
- **Status:** backlog
- **Opened:** 2026-07-11, second blocker of the New-ZenGL Pascal ladder
  ([[feature-game-library-candidate-suite]] slice C).

## Symptom

A `{$...}` directive inside a `(* ... *)` block comment is evaluated instead of
being skipped as comment text:

```pascal
program tcmt;
(* dead block
  {$if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L}
  junk
  {$endif}
*)
begin
end.
```

```
pascal26:0: error: conditional directive: unexpected character ()
```

FPC treats a `{ }` (and any `{$...}`) inside a `(* *)` comment as plain comment
content — one comment type may appear inside the other. PXX's lexer processes
the brace directive anyway, so commented-out junk (here: machine-translated C
preprocessor lines with `&&` in a Khronos-generated ZenGL unit,
`zgl_gltypeconst.pas:612-660`) kills the compile.

## Where hit

- `library_candidates/zengl/Zengl_SRC/srcGL/zgl_gltypeconst.pas` — a large
  `(* ... *)`-commented block of half-translated C `#if` lines. Blocks every
  ZenGL unit that pulls `zgl_gltypeconst`.
- **Synapse (2026-07-11 re-probe at v201):** `external/synapse/jedi.inc` has a
  `(* ... *)` documentation block (lines 48-699) containing example directives,
  including `{$IF Declared(RTLVersion) and (RTLVersion >= 14.2)}` (line 501) —
  PXX evaluates it, chokes on `14.2` ("unexpected character", reported at
  synautil.pas:458 through the include splice), and EVERY Synapse unit dies at
  `{$I jedi.inc}`. This regressed the Synapse compile-check from its previous
  wall ("too many array constant elements") to line 52 — earlier probes (v83)
  got past jedi.inc, so either the comment/directive handling changed since or
  the doc block did. Fixing this unblocks the whole
  [[feature-synapse-compile-check]] ladder at once.

## Acceptance

- `{`, `}`, and `{$...}` inside `(* ... *)` are comment text (and vice versa:
  `(*`/`*)` inside `{ }` already behave per the nested-comments setting).
- The ZenGL repro above compiles; self-host byte-identical (mind the
  [[project_nested_comment_brace_selfhost_landmine]] class of hazards: comment
  handling changes can desync the 2-step self-host — reseed, don't bisect).
- A lexer test covers directive-in-(**)-comment and brace-in-(**)-comment.

## Resolution (2026-07-12, opus-night)

TWO distinct bugs were behind the symptom; both fixed:

1. **Include-expansion pass processed directives inside comments/strings**
   (`compiler/elfwriter.inc`): the pre-lex `{$include}` expansion scanned raw
   text for `{$` with no awareness of `(* *)` comments, `//` line comments, or
   string literals (it already skipped `{ }`). ZenGL's zgl_gltypeconst and the
   tcmt repro died here. The scan now skips all three (mirroring the lexer's
   comment rules; the main lexer's (* *) scanner was already correct).
2. **{$MODE DELPHI} leaked NestedComments across units**
   (`compiler/parser.inc` ParseUsesUnit): Synapse's jedi.inc sets MODE DELPHI
   (NestedComments off) and every lib/rtl unit lexed AFTER it broke on
   nested-brace doc comments ("unexpected character" at the first orphaned
   `}`). Fix: per-unit scoping like the existing CaseSensitiveMode precedent —
   caller state saved/restored AND the child starts from the FPC default
   (True), since FPC lexes each unit under its own mode, not the includer's.

Also defused two nested-brace doc comments in platform_backend.pas that only
lexed by grace of NestedComments=on. Result: tcmt repro compiles; ZenGL
zgl_gltypeconst advances to its real next wall (`uses X` — no X11 unit);
Synapse synautil now parses ALL the way into semantics (`undefined variable
DayOfWeek` — an RTL surface gap, Track B). Gate: 2-step self-host
byte-identical + testmgr FULL 1131/1131 GREEN.
