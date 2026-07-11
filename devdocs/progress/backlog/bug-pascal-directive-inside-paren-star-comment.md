---
prio: 55
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

`library_candidates/zengl/Zengl_SRC/srcGL/zgl_gltypeconst.pas` — a large
`(* ... *)`-commented block of half-translated C `#if` lines. Blocks every
ZenGL unit that pulls `zgl_gltypeconst`.

## Acceptance

- `{`, `}`, and `{$...}` inside `(* ... *)` are comment text (and vice versa:
  `(*`/`*)` inside `{ }` already behave per the nested-comments setting).
- The ZenGL repro above compiles; self-host byte-identical (mind the
  [[project_nested_comment_brace_selfhost_landmine]] class of hazards: comment
  handling changes can desync the 2-step self-host — reseed, don't bisect).
- A lexer test covers directive-in-(**)-comment and brace-in-(**)-comment.
