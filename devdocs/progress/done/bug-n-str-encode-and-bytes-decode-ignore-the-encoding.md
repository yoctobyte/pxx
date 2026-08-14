---
track: N
prio: 25
type: bug
summary: "str.encode(enc) and bytes.decode(enc) IGNORE their encoding argument and always use UTF-8 — 'hé'.encode('latin-1') returns 3 UTF-8 bytes where CPython gives 2, encode('ascii') silently succeeds where CPython raises, and decode never raises UnicodeDecodeError. Silent wrong bytes, and it blocks an honest codecs shim"
status: done
owner: agent-AN
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

## 2026-08-11 (claude-A) — claimed, scoped, released without changes

Read the code before starting. The shape is bigger than "pass the argument
through", and the reason is worth recording so the next session does not
rediscover it:

`pystr_encode(const s: AnsiString): TPyBytes` takes **no encoding parameter at
all** — the frontend drops the argument, and the body is a byte-for-byte copy.
So this is not a case of an ignored parameter but of a missing one, on both
sides.

The deeper constraint: **pxx strings ARE byte strings.** `"hé"` in source is
already UTF-8 bytes, so encoding it to latin-1 means DECODING those bytes to
code points and re-encoding — a real codec, not a relabelling. Same in reverse
for `decode`. That is why the table in this ticket shows utf-8 agreeing and
everything else diverging: utf-8 is the one encoding for which the identity copy
is right.

So the work is: a code-point layer between the two byte forms, `encode`/`decode`
entries that take the encoding, `UnicodeEncodeError` / `UnicodeDecodeError` /
`LookupError` for the cases CPython raises on, and a frontend that passes the
argument. Worth doing in one pass — a half-set of encodings is how you get a
different silent wrong answer.

Released unchanged rather than started at the end of a long session, since a
codec landed half-way is worse than one not started.

## Resolution

Both directions honour the argument now, through code points, with one place
deciding what an encoding NAME means.

### Shape

The internal representation of a NilPy str is UTF-8, so neither direction can be
a byte copy any more except for utf-8 itself. Both go through code points:
decode the source to code points, encode those to the target. `PyEncCode` is the
single name→codec map, with CPython's alias spellings (`utf8`, `u8`, `latin1`,
`l1`, `cp819`, `iso8859-1`, …) and its `-`/`_`/space normalisation, so `UTF_8`,
`utf-8` and `Utf 8` are one encoding.

Implemented: `utf-8`, `ascii`, `latin-1`/`iso-8859-1`, `utf-16le`/`be`,
`utf-32le`/`be`, and `utf-16`/`utf-32` with a BOM (emitted on encode, honoured
on decode, defaulting to LE without one). `errors=` is `strict` (raise),
`replace`, `ignore` — and an unknown handler name is a `LookupError`, as in
CPython.

Anything else raises **`LookupError` by name**, which is the ticket's call:
returning UTF-8 bytes labelled `big5` is a wrong answer no caller can detect;
refusing is a missing feature a caller can. Recorded with its honest cost in
`nilpy-semantics-divergences.md` — a program passing only ASCII through an
unimplemented codec worked in CPython and is refused here.

### The decode half is the one that was quietly dangerous

`decode` did not merely ignore the encoding, it never RAISED: invalid input
became U+FFFD. Encoding-sniffing code — which is what webencodings and html5lib
ARE — detects a wrong guess precisely by catching `UnicodeDecodeError`, so every
guess looked right and the wrong branch was taken silently. Strict decode now
validates, including UTF-8 itself: a truncated or ill-formed sequence is
rejected rather than substituted, even though the internal form is our own
output.

### Two frontend facts this ran into

- **`.encode`'s arguments were SKIPPED AS TOKENS**, not parsed (`wantArgs = -4`),
  because `errors="replace"` is a keyword argument and a bare `errors` is not an
  expression. New mode `-11` parses them and consumes a leading `encoding=` /
  `errors=`; both names are fixed and in declaration order, so nothing has to be
  re-ordered.
- **`FindProc` never consults overloads** — the `-9` case says so outright
  ([[bug-nilpy-stdlib-shim-table-cannot-reach-an-overload]]). So the pylib entry
  points are one name per arity (`pystr_encode`, `pystr_encode_enc`,
  `pystr_encode_enc_err`) rather than the Pascal overloads I first wrote, which
  would have silently kept binding the zero-argument form.

### Verified

`test/test_nilpy_encode_decode_codecs.npy` — 26 rows, **byte-identical to
CPython**, including surrogate pairs for an astral-plane character
(`"a𝄞b"` through utf-16le), BOM round-trips, both keyword spellings, all three
error handlers, and the refusals in both directions. Compared with `diff -u`
against an `.expected` file rather than an inline `printf`, since the output
contains non-ASCII and a U+FFFD.

Every pre-existing test that touches `.encode`/`.decode` re-diffed against
CPython and unchanged: `bytes_hex`, `bytes_decode`, `bytearray_vs_bytes`,
`encode`, `method_str_chain`, `method_kwarg`, `str_method_subscript`.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary), before and after the pin. **Pinned (v307)** — `pylib.pas` is the
runtime of a compiled `.npy` program, so not a gate requirement, but without it
the fix does not reach programs built with `$(PXX_STABLE)`. Frozen builtin set
unchanged at 8 files.

### What this unblocks

[[feature-nilpy-codecs-shim]]: `codecs.lookup(name)` can now delegate to
`PyEncCode` and the two entry points instead of inheriting an ignored argument.
That is the normalise-don't-special-case shape the ticket asked for — one place
decides, the shim delegates.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
