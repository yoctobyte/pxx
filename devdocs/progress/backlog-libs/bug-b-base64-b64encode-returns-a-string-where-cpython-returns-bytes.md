---
slug: bug-b-base64-b64encode-returns-a-string-where-cpython-returns-bytes
title: "base64.b64encode returns AnsiString where CPython returns bytes, so .decode() on the result fails"
track: B
prio: 45
type: bug
blocked-by: []
status: new
created: 2026-09-10
found: 2026-09-10
found-by: frank-user, while proving the Pascal-library-imported-by-NilPy pattern works
owner: ""
summary: "MEASURED 2026-09-10 at 546d4dcbd305, by running the same two lines on both runtimes. `import base64` from NilPy WORKS -- it reaches lib/rtl/base64.pas and b64encode/b64decode round-trip correctly, which is the proof that the owner's `implement in pascal, import transparently from nilpy' architecture is real and already shipping. The one divergence is the RETURN TYPE: `print(base64.b64encode(b\"hello from pxx\"))` gives `aGVsbG8gZnJvbSBweHg=` here and `b'aGVsbG8gZnJvbSBweHg='` under CPython, because base64.pas declares `function b64encode(const data: Variant): AnsiString` where CPython's b64encode returns BYTES. The VALUES are right and the TYPE is not, so this is invisible to any test that only prints or compares text, and it bites a real program the moment it writes the idiomatic `base64.b64encode(x).decode()` or concatenates the result with other bytes. b64decode has the mirror of it. THE SPELLING IS ALREADY PROVEN AND THIS IS NOT RESEARCH: TPyBytes is a supported return type in the tree (mimic_urllib_error.pas declares `function HTTPError.read(n: Integer): TPyBytes'), and base64.pas ALREADY uses TPyBytes internally at :34 for the INPUT side -- it accepts bytes and then hands back a string, so only the outward half is missing. CHECK THE CALLERS BEFORE FLIPPING IT: the Pascal-facing Base64Encode/Base64EncodeStr must keep returning AnsiString (they are the Pascal surface and nothing about this touches them), and any existing NilPy caller that treats the result as str will change behaviour -- which is the point, but it should be a measured list rather than a surprise. The oracle is free and is how this was found: tools/pydiff.py, or literally running the file under both."
---

# `b64encode` returns str where CPython returns bytes

## How it was found, which is the part worth keeping

Not from a report. I was checking whether the owner's stated architecture —
*"implement libraries in pascal by default, and have them importable to nilpy,
transparently"* — actually works, because `lib/rtl/base64.pas` carries both
surfaces in one unit and is the template for it:

```pascal
function Base64Encode(const data: TByteArray): AnsiString;   { the Pascal surface }
function b64encode(const data: Variant): AnsiString;         { the Python surface }
```

Two lines on both runtimes:

```python
import base64
print(base64.b64encode(b"hello from pxx"))
print(base64.b64decode("aGVsbG8gZnJvbSBweHg="))
```

| | |
| --- | --- |
| pxx | `aGVsbG8gZnJvbSBweHg=` / `hello from pxx` |
| CPython | `b'aGVsbG8gZnJvbSBweHg='` / `b'hello from pxx'` |

**The pattern works. The types are off by one layer.** That is a good outcome for
the architecture and a real bug for a consuming program.

## Why no existing test could have caught it

The bytes are identical and only the `repr` differs, so any assertion that
prints, compares text, or round-trips through this module agrees with CPython.
What breaks is a program doing what programs actually do with base64:

```python
token = base64.b64encode(raw).decode()      # AttributeError: no decode on a str
payload = b"Basic " + base64.b64encode(cred) # str + bytes
```

This is the assertion-class problem from CLAUDE.md in its cheapest form: the
defect is in the TYPE and every value check passes. The instrument that sees it
is a diff of the two runtimes' `repr`, which costs one command.

## The fix is a spelling already in the tree

`TPyBytes` is a supported return type — `mimic_urllib_error.pas` has
`function HTTPError.read(n: Integer): TPyBytes`. And `base64.pas` already uses
`TPyBytes` at `:34` on the **input** side, so the unit accepts bytes and then
hands back a string; only the outward half is missing.

Two things to check rather than assume:

- `Base64Encode` / `Base64EncodeStr` are the **Pascal** surface and must keep
  returning `AnsiString`. Nothing here touches them.
- Any existing NilPy caller treating the result as `str` changes behaviour. That
  is the intent, but produce the list first — `grep` the corpora and
  `lib/**` — so it is a measured change and not a surprise.

## The general question behind it

`base64` is the one unit I happened to diff. **Every `lib/rtl` unit carrying a
Python surface has this exposure**, and nothing systematically checks the
returned TYPE against CPython. `configparser.pas` and `mimic_codecs.pas` use
`TPyBytes` too and were not examined. A sweep that runs each Python-facing entry
point under both runtimes and diffs the `repr` — not the value — would find the
rest in one pass, and it is the kind of fixture that cannot pass by agreeing
with a stale constant. Worth a ticket of its own if anyone takes this one.
