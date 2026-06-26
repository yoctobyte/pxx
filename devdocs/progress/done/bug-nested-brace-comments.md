# bug: `{ }` comments do not nest

- **Type:** bug (Track A — lexer)
- **Status:** done
- **Found:** 2026-06-23, writing PCL/solitaire comments
- **Closed:** 2026-06-23
- **Severity:** low (cosmetic, but surprising — silently turns comment text into code)

## CORRECTION (2026-06-24)

This over-reached: real FPC does **not** nest `{ }` / `(* *)` by default — a `{`
inside a `{ }` comment is plain text. The True default below broke the common
idiom `{ consume '{' }` (lib/rtl/json.pas). Default reverted to False in
`bug-nested-comment-breaks-fpc-brace`; nesting is now opt-in via
`{$NESTEDCOMMENTS ON}` only. The original symptom (`{ outer { inner } }`) is no
longer "fixed" by default — that idiom is non-FPC and must use the directive.

## Resolution (2026-06-23)

The nested-comment machinery already existed (lexer.inc: `commentDepth` tracking
for `{ }` and `(* *)`, plus the `{$NESTEDCOMMENTS ON/OFF}` directive), gated on a
`NestedComments` flag that defaulted to False. Flipped the default to True — the
dialect default the owner wanted (FPC nests too). `{$NESTEDCOMMENTS OFF}`
disables it.

`{ outer { inner } still comment }` and `(* a (* b *) c *)` now compile,
byte-identical to FPC. Self-host is unaffected: the ~169 inner-brace comments in
the compiler source (e.g. `{ push {r4-r11, lr} }`) are all brace-balanced, so the
nested scan ends at the same point as the old flat scan (both modes skip the
whole comment, identical token stream — verified by the byte-identical
self-host). Gate: `make test` (self-host byte-identical) + FPC oracle. Closes
bug-nested-brace-comments.

## Symptom

A `{ ... }` comment containing an inner `{ ... }` ends at the first inner `}`;
the remaining text is then lexed as code:

```pascal
program t;
begin
  { outer { inner } still comment }
  writeln(1);
end.
```

→ `error: unexpected character` (on `still comment }`).

Control — a plain comment compiles + runs fine:

```pascal
{ plain comment }
writeln(1);   { prints 1 }
```

## Expected

Per the dialect owner, nested brace comments should be supported by default
(unless explicitly disabled via a mode/compiler switch). The lexer should track
brace depth so `{ a { b } c }` is a single comment.

## Notes

- Worked around in PCL/solitaire/test comments by removing inner braces; per the
  no-workaround policy those should be reverted to natural nested form once this
  lands. Affected comments mention `GtkAllocation`/`GdkEventButton` field layouts.
- Check `(* *)` and `//` interaction / whether a switch already exists.
