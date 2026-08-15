---
track: B
prio: 50
type: feature
blocked-by: []
summary: "A `mimic_codecs` unit so `import codecs` resolves: the charmap trio (build/decode/encode), lookup/register/CodecInfo and the five base classes. Measured as the exact surface webencodings needs, which is the bottom rung of the webencodings -> tinycss2 -> html5lib ladder in feature-nilpy-thirdparty-libraries-as-targets."
status: done
owner: claude-B
---

# `mimic_codecs` — the stdlib-C edge the html5lib ladder starts on

- **Type:** feature (library) — **Track B** (`lib/**`, built with `$(PXX_STABLE)`)
- **Opened:** 2026-08-13, from the measurement in
  [[feature-nilpy-thirdparty-libraries-as-targets]]: `webencodings` is a class-4
  dependency (stdlib-C edge), not class 1. Its `labels.py` compiles clean with
  pxx today; `__init__.py` and `x_user_defined.py` both stop at
  `no unit named codecs and no shim mimic_codecs`.

## The surface, measured — not a guess at "all of codecs"

Everything `webencodings` touches, and nothing else:

```
codecs.lookup(name) -> CodecInfo        codecs.register(search_function)
codecs.CodecInfo(...)
codecs.charmap_build(decoding_table)
codecs.charmap_decode(input, errors, decoding_table)
codecs.charmap_encode(input, errors, encoding_table)
base classes: Codec, IncrementalDecoder, IncrementalEncoder,
              StreamReader, StreamWriter
```

The charmap trio is the substantive part and it is small: a 256-entry table maps
bytes to code points and back, with an `errors` policy (`strict` raising,
`replace`, `ignore`) — the same shape the RTL's existing encoding work already
has to reason about.

`lookup` needs a registry keyed by the normalised encoding name, seeded with
whatever encodings we can actually decode, plus `register` so a library can add
its own search function (which is exactly how webencodings installs
`x-user-defined`).

## Naming

`mimic_codecs`, per `devdocs/dev/python-compat-tiers.md`: `import codecs`
RESOLVES to it through the import resolver, so no file in the tree carries the
stdlib's name and `--no-shims` can make the substitution an error.

## Why it is worth doing beyond one library

Class 4 is the recurring cost every Python app pays — `codecs re zlib json
hashlib socket ssl` — and it is the same list for every app, not a per-library
problem. `codecs` is the one the html5lib ladder hits FIRST, and it is the
smallest of them.

## Gate

`make lib-test` green, plus the real forcing test: `webencodings/__init__.py`
and `x_user_defined.py` compile with pxx, and a `.npy` that decodes and encodes
through `x-user-defined` matches CPython byte for byte.

## 2026-08-15 (Track B) — `lib/rtl/mimic_codecs.pas` lands, CPython-diffed

`import codecs` resolves to it through the resolver's `mimic_` fallback (the
compile prints `note: codecs -> mimic_codecs (shim, subset)`), so no file in the
tree carries the stdlib's name and `--no-shims` still turns the substitution
into an error.

### The surface, as built

Exactly the measured list in this ticket, re-checked against
`library_candidates/webencodings` rather than taken from the ticket text:
`charmap_build` / `charmap_decode` / `charmap_encode`, `lookup` / `register` /
`CodecInfo`, and the five base classes `Codec`, `IncrementalEncoder`,
`IncrementalDecoder`, `StreamReader`, `StreamWriter`. Added beyond it, because
they are one line each once the tables exist and encoding-detection code reaches
for them by name: `codecs.encode` / `codecs.decode` and the five `BOM_*`
constants.

Design notes worth keeping:

- **`lookup` returns a Variant, not a `CodecInfo`.** A registered search function
  is Python code and answers a Python object — possibly a CodecInfo built in
  NilPy, not one of ours — so typing the result would force a downcast on a
  value we do not own. Callers write `lookup(n).decode(...)` either way.
- **`charmap_build` answers a dict from CODE POINT to byte.** CPython's answers
  an opaque `EncodingMap` that only `charmap_encode` ever consumes, so nothing
  portable can tell the difference, and a dict is readable in a debugger.
  First-byte-wins on a duplicate character, matching CPython's build.
- **`replace` substitutes U+FFFD decoding and `'?'` encoding.** Two different
  characters; the asymmetry is CPython's and is deliberate.
- The unit walks UTF-8 itself (`CpAt`) rather than indexing AnsiStrings, because
  a decoding table is a *str* whose characters are not its bytes — the
  x-user-defined table maps the high byte range onto U+F780..U+F7FF, so every
  entry above 127 is three bytes wide.

### Gate

`test/lib_codecs.npy` runs **unchanged under python3** and lib-test diffs the two
outputs — the nilsh pattern, and the only way to know a charmap codec is right
rather than merely self-consistent. It covers the x-user-defined round trip
(built the way `x_user_defined.py` builds it), the three error policies including
the `UnicodeDecodeError` raise, and name normalisation folding case/underscore/
hyphen together. **Output identical to CPython.** `make lib-test` GREEN with
`lib-test: mimic_codecs matches CPython` in the log.

### The forcing test: HALF of it passes, and the other half is not this lane's

This ticket's gate asks for three things. Measured, on pinned v339:

- *"a `.npy` that decodes and encodes through `x-user-defined` matches CPython
  byte for byte"* — **YES**, that is `test/lib_codecs.npy` above, using
  webencodings' own table construction.
- *"`make lib-test` green"* — **YES**.
- *"`webencodings/__init__.py` and `x_user_defined.py` compile with pxx"* —
  **NO**, and no longer for a codecs reason. Each now stops on a different gap
  in another lane:
  - `x_user_defined.py`:
    [[bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler]] — the
    file opens `class Codec(codecs.Codec)`, which makes the compiler **loop
    forever** with no diagnostic. Four lines reproduce it, and it reproduces
    against a hand-written Pascal unit too, so it is not shim-specific. Behind
    it sits
    [[bug-nilpy-multiple-inheritance-from-an-imported-base-is-refused]]
    (`class StreamWriter(Codec, codecs.StreamWriter)`).
  - `__init__.py`: [[bug-a-bytes-has-almost-none-of-its-python-methods]] —
    `b.lower()` in the label normaliser, with `b.startswith()` waiting on the
    next line. `bytes` has `endswith` but not `startswith`, which says how that
    surface grew.

Resolved rather than parked, because the deliverable — the shim — is complete,
gated and CPython-diffed, and nothing further about *codecs* is what the ladder
is waiting on. The remaining distance is tracked on
[[feature-nilpy-thirdparty-libraries-as-targets]], which now records that a shim
only reveals the next wall and that its per-file table is the FIRST wall, not
the remaining work.

Also closes [[feature-nilpy-codecs-shim]], which asks for the same unit from the
other direction and was opened first.

## Log
- 2026-08-15 — resolved, commit 4aee95c53.
