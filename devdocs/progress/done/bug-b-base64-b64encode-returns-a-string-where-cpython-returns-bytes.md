---
slug: bug-b-base64-b64encode-returns-a-string-where-cpython-returns-bytes
title: "base64.b64encode returns AnsiString where CPython returns bytes, so .decode() on the result fails"
track: B
prio: 45
type: bug
blocked-by: []
status: done
created: 2026-09-10
found: 2026-09-10
found-by: frank-user, while proving the Pascal-library-imported-by-NilPy pattern works
owner: frankb-56
summary: "RESOLVED 2026-09-14 (frankb-56). b64encode and b64decode return TPyBytes; the Pascal surface (Base64Encode/Base64EncodeStr) is untouched and still returns AnsiString. THE CALLER LIST THIS TICKET ASKED FOR WAS EMPTY -- measured before the flip, no consumer of either name exists outside base64.pas, so nothing changed behaviour. THE FLIP EXPOSED A SECOND BUG THAT HAD NEVER BEEN REACHABLE: b64decode fed its argument to pystr_of, which does not render a TPyBytes as characters, so b64decode(b64encode(b'hi')) answered b'' against CPython's b'hi' while the str argument was correct throughout -- silent and total rather than partial, and unreachable until b64encode started producing bytes to hand it. pymarshal.PyToText is the fix. AND THE GENERAL QUESTION IS NOW A FIXTURE, which is the part worth keeping: test/lib_pysurface_repr.py runs the python half of base64 and zlib under pxx AND CPython and diffs the outputs, wired into make lib-test; every row prints a repr() or a type() and never a bare value. Its positive control is unusually strong -- against the pre-fix base64.pas the fixture does not merely differ, it DOES NOT COMPILE, because b64encode(x).decode() is a str method call. It covers base64 and zlib ONLY: configparser, mimic_codecs, io, json and re carry python surfaces nobody has examined, and the fixture is where they go."
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

## RESOLVED 2026-09-14 (frankb-56, Track B)

`b64encode` and `b64decode` return `TPyBytes`. The Pascal surface is untouched.

**The caller list the ticket asked for is EMPTY, measured before the flip** — a
grep of every `.py`, `.npy`, `.pas` and `.inc` in the tree found no consumer of
either name outside `base64.pas` itself. So the "measured list rather than a
surprise" cost one command and came back with nothing to warn anyone about.

### The flip exposed a second bug that had never been reachable

`b64decode` fed its argument to `pystr_of`, and `pystr_of` on a `TPyBytes` does
not render the bytes as characters. Measured:

    base64.b64decode(base64.b64encode(b"hi"))   ->  b''      (CPython: b'hi')
    base64.b64decode("aGk=")                    ->  b'hi'    (agrees)

**The bytes arm was broken from the start and nothing could reach it**, because
every caller passed a `str` and nothing in the tree produced `bytes` to hand it
— until `b64encode` above started returning them. It fails *silently and
totally* rather than partially: the decoder finds no alphabet characters in
`pystr_of`'s rendering and returns empty, which is a plausible value.
`pymarshal.PyToText` is the fix and carries the measurement.

### The general question is now a fixture, which is the part worth keeping

The ticket's closing paragraph — *"a sweep that runs each Python-facing entry
point under both runtimes and diffs the `repr`, not the value ... worth a ticket
of its own"* — is `test/lib_pysurface_repr.py`, wired into `make lib-test`. One
file, run under pxx AND CPython, outputs diffed. Every row prints a `repr()` or
a `type()` and never a bare value, and the header says why adding a value row
would quietly retire the guard.

**Positive control, and it is unusually strong:** against the pre-fix
`base64.pas` the fixture does not merely differ, it **does not compile** —
`b64encode(x).decode()` is a str method call and NilPy refuses it with the list
of str methods it does have. That is the AttributeError this ticket predicted,
arriving at compile time.

**What it deliberately does NOT assert:** deflate output. Which matches an
encoder finds is latitude, so a row printing `zlib.compress(x)` or its length
would be red for no defect. The compressed half is asserted the only way that is
a claim — a stream CPython produced, frozen into the fixture, must decompress to
the known plaintext.

### Covered today: base64 and zlib. NOT covered: everything else

`configparser.pas`, `mimic_codecs.pas`, `io.pas`, `json.pas`, `re.pas` and the
rest carry Python surfaces that were not examined. The fixture is the place to
add them and each is a few lines; nobody has done it, and saying so is the point
— this closes the two units that were measured, not the class.

## Log
- 2026-09-14 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6b45b991b.
