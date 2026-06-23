# bug: `{ }` comments do not nest

- **Type:** bug (Track A — lexer)
- **Status:** backlog
- **Found:** 2026-06-23, writing PCL/solitaire comments
- **Severity:** low (cosmetic, but surprising — silently turns comment text into code)

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
