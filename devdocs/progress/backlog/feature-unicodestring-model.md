---
prio: 40
---

# A real UnicodeString / WideChar model (UTF-16), or an honest refusal

- **Type:** feature (string model — Track A/P)
- **Status:** backlog — opened 2026-07-13.
- **Blocks:** fcl-json's `jsonparser`/`jsonscanner` (the `\uXXXX` escape path). fpjson itself
  (the DOM, the formatter, every accessor) is DONE and does not need this.

## The wall, exactly
`jsonscanner.pp` decodes a `\uXXXX` escape into a UTF-16 code unit and, for a surrogate pair,
does:

```pascal
S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));
```

`WideChar(x) + WideChar(y)` is a two-element **UTF-16 string**. pxx has ONE string model —
bytes — so `WideChar` is a 2-byte ORDINAL here, `+` is integer addition, and `String(...)` of
the result is rejected. The rejection is correct; there is nothing to silently do instead.

## Why this is a model decision, not a function
The rest of the RTL is already honest about it and says so at the declaration:
- `UTF8Decode`/`UTF8Encode` are the IDENTITY (lib/rtl/sysutils) — for ASCII the two agree
  exactly, for multi-byte UTF-8 they do not;
- `DefaultSystemCodePage` reports `CP_UTF8`, because the bytes really do pass through
  untouched;
- `WideChar` casts to a 2-byte ordinal.

Every one of those is right for a byte-transparent RTL. What is missing is a genuine UTF-16
`UnicodeString`/`WideString` with 2-byte elements — indexing, Length, concatenation, and the
UTF-8 ⇄ UTF-16 transcoders. That touches the string model (tyAnsiString / tyString / a new
tyWideString), the managed-string ARC helpers, and the literal path. It is a real feature, not
a shim, and faking it would be exactly the "silently wrong" failure this corpus keeps finding.

## Scope note
JSON in the wild is overwhelmingly ASCII or plain UTF-8 (which passes through byte-for-byte).
Only `\uXXXX` escapes hit this. So an intermediate step is defensible IF it is loud: decode
`\uXXXX` in the BMP directly to UTF-8 bytes (no UTF-16 intermediate), and REFUSE a surrogate
pair with a clear runtime error rather than mangling it. That would need a patched scanner,
i.e. a fork — which the corpus rules say to avoid — so prefer doing the model properly.

## Gate
`make test` + self-host byte-identical + cross.
