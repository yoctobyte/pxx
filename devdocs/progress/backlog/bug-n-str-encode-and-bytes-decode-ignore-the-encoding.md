---
track: N
prio: 25
type: bug
summary: "str.encode(enc) and bytes.decode(enc) IGNORE their encoding argument and always use UTF-8 — 'hé'.encode('latin-1') returns 3 UTF-8 bytes where CPython gives 2, encode('ascii') silently succeeds where CPython raises, and decode never raises UnicodeDecodeError. Silent wrong bytes, and it blocks an honest codecs shim"
---

# `str.encode` / `bytes.decode` ignore the encoding argument

- **Type:** bug (silent wrong answer) — Track N
- **Opened:** 2026-08-09
- **Found by:** Track B, scoping [[feature-nilpy-codecs-shim]] against the real
  webencodings sources. A `codecs.lookup(name)` has to hand back something whose
  `.encode`/`.decode` are correct FOR THAT ENCODING, so the first question was
  what the existing builtins do.

## Measured (pinned v252, CPython 3 as the oracle)

`"hé".encode(enc)`:

| enc | pxx | CPython |
| --- | --- | --- |
| `utf-8` | `3 [104, 195, 169]` | `3 [104, 195, 169]` — agree |
| `latin-1` | `3 [104, 195, 169]` | **`2 [104, 233]`** |
| `utf-16le` | `3 [104, 195, 169]` | **`4 [104, 0, 233, 0]`** |
| `ascii` | `3 [104, 195, 169]` | **`UnicodeEncodeError`** |

`bytes([104, 233]).decode(enc)`:

| enc | pxx | CPython |
| --- | --- | --- |
| `utf-8` | `'h\\ufffd'` | **`UnicodeDecodeError`** |
| `latin-1` | `'h\\ufffd'` | **`'hé'`** |
| `utf-16le` | `'h\\ufffd'` | **`'\\ue968'`** |

The argument is not consulted in either direction. Both always do UTF-8, and
neither raises: `encode('ascii')` of a non-ASCII string succeeds, and `decode`
substitutes U+FFFD where CPython reports invalid input.

**It looks right on ASCII**, which is why it has survived — `"hi".encode(x)` is
2 bytes for every x, and most test strings are ASCII. The first non-ASCII
character is where it goes wrong, silently.

## PRIORITY CALL (user, 2026-08-09): low — and here is why that is right

Filed at 60 on pattern-match ("silent wrong bytes" = the worst class). Lowered
to 25 on the user's steer: *divergence is not an issue as long as the result is
correct; as long as applications work as expected, the internal encoding does
not matter.*

The distinction that makes that correct, and which the original write-up buried:

- **Internally we are CONSISTENT.** A pxx program doing `s.encode('latin-1')`
  and later `.decode('latin-1')` round-trips perfectly, because both sides
  ignore the argument the same way. Self-contained programs are unaffected.
- **The failure is at the BOUNDARY**, when bytes leave the program: written to a
  file declared latin-1, put on a socket, handed to a C library. Another reader
  sees mojibake (`hÃ©`).
- **utf-8 is already correct**, and it is what essentially all modern code uses.
  Being wrong needs a non-utf-8 encoding AND a non-ASCII character AND a
  boundary crossing.

So applications work as expected because they are on the correct path already.
Re-raise if a real target actually hits it — the html5lib/webencodings stack is
the obvious candidate, since encoding handling is what those libraries ARE.

## Why it matters beyond the shim

This is the silent-wrong-output class, in the RTL's most-used direction. A
program writing `text.encode('latin-1')` to a file gets UTF-8 bytes and a
corrupt file, with nothing raised anywhere. `decode` swallowing invalid input is
the same failure in reverse: code that relies on `UnicodeDecodeError` to detect
a wrong-encoding guess — which is exactly what encoding-sniffing code does, and
exactly what webencodings and html5lib are for — silently takes the wrong branch.

## What it blocks

[[feature-nilpy-codecs-shim]] cannot be written honestly on top of this.
`codecs.lookup(name).decode(...)` would delegate to `bytes.decode`, inherit the
argument being ignored, and hand webencodings a wrong answer for every non-UTF-8
label — while looking like it worked. Per
`devdocs/dev/python-compat-tiers.md`, a shim must fail loudly rather than
approximate, so the shim waits on this.

Fixing it here rather than inside the shim is also the
normalise-don't-special-case call: one place decides what an encoding name
means, and `codecs.lookup` then delegates to it, instead of two mechanisms that
can disagree.

## Suggested shape

Honour the argument for the encodings that can be done correctly — `utf-8`,
`ascii` (raising outside 0..127), `latin-1`/`iso-8859-1`, the other single-byte
`iso-8859-*` (simple tables), `utf-16le`/`be`, `utf-32le`/`be`, `utf-16`/`utf-32`
with BOM — and **raise by name** for anything else (`big5`, `gb18030`,
`euc-jp`, `shift_jis`, …). Refusing an encoding is a missing feature; returning
UTF-8 bytes labelled as big5 is a wrong answer.

`errors=` ('strict' default, 'replace', 'ignore') is part of the same contract
and is currently unimplemented in effect — `strict` must raise.

## Gate

`make test-nilpy` green + a `.npy` whose expectations are CPython's own output
for the two tables above, including the raising cases.
