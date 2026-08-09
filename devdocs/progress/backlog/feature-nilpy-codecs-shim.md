---
track: B
prio: 40
type: feature
---

# `import codecs` — the next wall for the compile-real-libraries campaign

```
pascal26: error: import: no unit named codecs and no shim mimic_codecs
```

Loud, and it is a genuine missing stdlib module rather than a parse gap.

Found compiling **webencodings** (`feature-nilpy-thirdparty-libraries-as-targets`
step 3). That package's data module already compiles and runs correctly — its
214-entry label table answers `len(LABELS) == 214` — and its `__init__.py` stops
here at line 17. webencodings is *about* character encodings, so `codecs` is not
incidental to it.

## What is actually needed

Not all of `codecs`. webencodings uses the lookup/decode surface:

- `codecs.lookup(name)` → a codec info object with `.name`
- `codecs.decode` / `codecs.encode` for the encodings it maps onto
- the incremental decoder shape for streaming

Worth scoping against the real usage in `webencodings/__init__.py` and
`x_user_defined.py` before writing anything, rather than aiming at the whole
module.

It also unblocks the rest of the stack: `tinycss2` and `html5lib` both decode
bytes, and `html5lib` is the biggest single win named in the campaign ticket.

## Note on the shape

`mimic_codecs` is the resolver's fallback unit name, so the shim lands as
`lib/**/mimic_codecs.pas` like the other shims. The encodings themselves are
data, and NilPy strings are bytes today — so the honest first version supports
the ASCII/latin-1/utf-8 subset and REFUSES the rest by name rather than
silently mis-decoding, which is the failure mode that would be hardest to spot
in a browser engine.

## Gate

`make lib-test` + compiling `webencodings/__init__.py` as source, and its own
upstream `tests.py` as the differential oracle once it runs.
