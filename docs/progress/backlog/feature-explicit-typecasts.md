# Explicit type-casts (`Char`/`Boolean`/`String` and a general `TypeName(expr)`)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18

## Motivation

Type-casting in PXX is ad-hoc: the factor parser (`parser.inc` ~2372) has a
hardcoded allowlist of cast tokens, not a general `TypeName(expr)` mechanism.
Surveyed 2026-06-18 (surfaced while wiring managed strings on ESP, but
target-independent — same char/shortstring/ansistring typing family as the
literal-concat fold fix):

| Cast | Parses | Notes |
|---|---|---|
| `Integer`/`LongWord`/`Byte`/`Word`/`Cardinal` | ✓ | collapse to `tkInteger_T`, passthrough |
| `Pointer` | ✓ | passthrough |
| `Ord` / `Chr` | ✓ | char<->int passthrough builtins |
| `PChar(s)` | ✓ | inline-string -> `const char*` adapter |
| **`Char(x)`** | ✗ | `tkChar_T` cast not wired -> "expected expression" |
| **`Boolean(x)`** | ✗ | `tkBoolean_T` not wired |
| **`String(x)`** | ✗ | `tkString_T` not wired |

Not urgent: `Boolean` and `Char` are easily worked around today (`Ord`/`Chr`,
or arithmetic), and `String(x)` has little use until external-library interop
grows (`PChar`->string already works for imports). Filed so the gap is tracked.

## Scope

- Add `tkChar_T`, `tkBoolean_T`, `tkString_T` to the factor parser's cast cases
  (mirror `tkInteger_T`): build an `AN_CALL` with `ASTIVal = -Ord(tk*_T)` and the
  right `ASTTk`.
- Codegen passthrough: add those ids to each backend's type-pun passthrough list
  (`Ord`/`Chr`/`tkInteger_T`/`tkLongWord_T` already passthrough on x86-64 line
  ~1300 and the ESP backends). `Char(x)` = low-byte (mask/passthrough on the
  value model), `Boolean(x)` = passthrough (nonzero semantics already hold),
  `String(x)` = char/PChar -> managed string (route to PXXStrFromLit /
  PCharToString as the existing inline-string store does).
- Consider a real general `TypeName(expr)` cast (named record/class/pointer
  reinterpret) instead of the token allowlist — larger, separate sub-task.

## Acceptance

- `Char(i)`, `Boolean(i)`, `String(c)` compile on all targets and produce the
  FPC-equivalent value; `make test` + `make cross-bootstrap` stay byte-identical.

## Notes

- Additive / target-independent, so byte-identity-safe.
- Related: the ESP literal-string-concat fold (commit e1c9198) and the
  managed-string typing work — same family of char/string conversions.
