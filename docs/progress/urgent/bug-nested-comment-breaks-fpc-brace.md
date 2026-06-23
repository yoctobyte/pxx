# bug: nested `{ }` comments break the FPC idiom `{ ... '{' ... }`

- **Type:** bug
- **Status:** urgent
- **Track:** A
- **Opened:** 2026-06-23
- **Breaks:** lib/rtl/json.pas (lib-test gate), and any source with a lone brace
  character inside a `{ }` comment.

## Summary

After `done/bug-nested-brace-comments`, `{ }` comments **nest**. But standard
Pascal / FPC `{ }` comments do **not** nest — a `{ }` comment ends at the first
`}`. Nesting them silently breaks the extremely common idiom of mentioning a
brace inside a comment:

```pascal
{ consume '{' }
writeln('after');     { <- swallowed: outer comment never closes }
```

The inner `{` opens a nested level; the single `}` closes only that level,
leaving the outer comment open, so it eats subsequent source until the next `}`
(or EOF). FPC compiles this fine.

## Repro (compiler only)

```pascal
program t;
begin
  { consume '{' }
  writeln('after comment');
end.
```

`pinned t.pas` → `error: undefined variable (interface)` (the comment swallowed
`writeln(...)` and beyond). Expected: compiles, prints `after comment`.

Found in `lib/rtl/json.pas:491` (`{ consume '{' }`), which fails to compile under
v44 → `examples/json/jsondemo.pas` breaks → `make lib-test` red.

## Expected (FPC semantics)

`{ }` comments do NOT nest; `(* *)` do not nest either; only the `(* { *)` /
`{ (* }` cross pairs and `{$...}` are special. A `{` inside a `{ }` comment is
plain text and must not open a nested comment. If nesting is wanted at all it
must be opt-in (a directive/mode), never the default — it is an FPC-compat break.

## Note

`done/bug-nested-brace-comments` should be re-examined: it likely over-reached.
Real FPC behaviour is non-nesting `{ }`. Track B hit this only now because the
v44 re-pin is the first stable to carry the nesting change together with libs
that mention braces in comments.

## Acceptance

The repro compiles and prints `after comment`; `make lib-test` passes
`jsondemo` again; `make test` (Track A self-host) stays green.

## Log
- 2026-06-23 — filed from Track B (surfaced running `make lib-test` after the v44
  re-pin). Not worked around — json.pas left idiomatic. Grep marker:
  `bug-nested-comment-breaks-fpc-brace`.
