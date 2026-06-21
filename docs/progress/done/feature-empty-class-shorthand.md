# Empty class descendant shorthand

- **Type:** feature
- **Track:** A
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** surfaced by `examples/chess` after `SysUtils.Exception` landed.

## Problem

FPC accepts an empty descendant declaration with a parent and no explicit
`end`:

```pascal
EChess = class(Exception);
```

PXX currently treats this as the start of a class body, consumes following type
declarations, and eventually fails later in the type section.

## Scope

- In type parsing, accept `T = class(TBase);` as a complete empty class
  declaration.
- Keep the existing full form working:

```pascal
T = class(TBase)
end;
```

## Acceptance

- A focused test can declare `E = class(Exception);` from `uses sysutils`.
- `examples/chess/chess.pas` gets past the `EChess` declaration.
- Existing class/inheritance tests still pass.

## Log

- 2026-06-20 - Opened after adding the Track B `Exception` base class to
  `lib/rtl/sysutils.pas`. The chess discovery gap moved from missing base class
  to this syntax form.
- 2026-06-20 - DONE (Track A). parser.inc: `if CurTok.Kind <> tkSemicolon` guard
  wraps the class body while-loop + `Expect(tkEnd)`. Semicolon seen after
  `class(TBase)` → skip body entirely, UClsSize still set from curFieldOff.
  `make test` green, byte-identical self-host. chess.pas now past EChess line
  (next gap: UpCase RTL). test/test_empty_class_shorthand.pas added.

**Resolved-in:** 1dd9873 (finalizing commit)
