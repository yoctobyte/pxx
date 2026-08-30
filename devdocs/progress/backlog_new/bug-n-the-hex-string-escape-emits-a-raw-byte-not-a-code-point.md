---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`'\\xNN'` for NN >= 0x80 puts a RAW BYTE in the string instead of code point U+00NN, producing a malformed string: '\\xe9' encodes to [233] not [195,169], and '\\x80' reports len() == 0 with ord() raising TypeError. chr(233), '\\u00e9' and a literal 'é' are all correct, so it is the \\x escape specifically."
status: backlog
owner: unassigned
---

# The `\xNN` string escape emits a raw byte, not a code point

- **Type:** bug — **Track N** (Nil-Python frontend, string-literal lexing).
- **Filed:** 2026-08-30 by frankB, found by the `codecs` differential in
  [[feature-b-sweep-mimic-shims-against-cpython]] — it presented as a codecs
  encode failure and is not one.
- Measured at pin v395 (`aa78a7faf63a`).

## What is wrong

In Python `'\xNN'` is **code point U+00NN**, not byte NN. For NN < 0x80 the two
coincide, which is why this was invisible. For NN >= 0x80 the escape here puts
the raw byte into the string's UTF-8 storage, leaving a string that is not
valid UTF-8 — so its length, its characters and its encoding are all wrong.

| literal | pxx: utf-8 bytes | pxx `len()` | CPython bytes | CPython `len()` |
| --- | --- | --- | --- | --- |
| `'\x41'` | `[65]` | 1 | `[65]` | 1 |
| `'\x7f'` | `[127]` | 1 | `[127]` | 1 |
| `'\x80'` | `[128]` | **0** | `[194,128]` | 1 |
| `'\xa0'` | `[160]` | **0** | `[194,160]` | 1 |
| `'\xe9'` | `[233]` | 1 | `[195,169]` | 1 |
| `'\xff'` | `[255]` | 1 | `[195,191]` | 1 |

`ord('\x80')` raises `TypeError: ord() expected a character, but string of
length 0 found`. CPython answers `128`.

**The `len()` column is the dangerous part.** A one-character string reports
length 0 or 1 depending on which byte it holds, because the code-point walker is
being asked to walk bytes that are not a valid encoding. `'\xe9'` reporting
length 1 is a *coincidence* of how 0xE9 mis-decodes, not correctness — an
earlier read of this bug concluded "the string model is fine" from exactly that
coincidence, having tested only `\xe9`.

## It is the `\x` escape alone

Everything else that names the same character is correct:

```
chr(233)   -> [195,169]   correct
'é'   -> [195,169]   correct
'é'        -> [195,169]   correct   (literal in UTF-8 source)
'\xe9'     -> [233]       WRONG
```

So the string representation, `chr()`, the `\u` escape and source-literal
decoding are all fine. The defect is confined to `\x` handling in the string
lexer, which appears to write the byte rather than encoding the code point.

## Blast radius

`'\xNN'` is ordinary Python and common in exactly the places it hurts: binary
protocol constants, test fixtures for encoding bugs, and any code copied from
CPython documentation. It produces a **corrupt string value** with no
diagnostic — nothing raises at the literal, and the damage surfaces later as a
wrong length, a wrong encode, or a `TypeError` from `ord()` far from the source.

It also **breaks test fixtures silently**, which is how it was found: the
`codecs` differential used `'\xe9'` to test high-byte encoding and the failure
looked like a `codecs.encode` bug. That differential now uses `chr(233)` and
says why.

## Note for whoever takes it

Check `b'\xNN'` (bytes literals) separately — there the byte IS the right thing
and the fix must not change it. The bug is that the *str* path uses the bytes
rule. Also check `'\NNN'` octal escapes, which have the same "code point, not
byte" semantics in Python and are likely to share the implementation.
