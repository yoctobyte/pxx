---
track: B
prio: 50
type: feature
blocked-by: []
summary: "A `mimic_codecs` unit so `import codecs` resolves: the charmap trio (build/decode/encode), lookup/register/CodecInfo and the five base classes. Measured as the exact surface webencodings needs, which is the bottom rung of the webencodings -> tinycss2 -> html5lib ladder in feature-nilpy-thirdparty-libraries-as-targets."
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
