---
track: B
prio: 40
type: feature
blocked-by: []   # bug-n-str-encode-and-bytes-decode-ignore-the-encoding landed; cleared 2026-08-15
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

## Blocked 2026-08-09 (Track B): the sources it must be scoped against are not here

This ticket's own instruction is the blocker — *"worth scoping against the real
usage in `webencodings/__init__.py` and `x_user_defined.py` before writing
anything, rather than aiming at the whole module"* — and `webencodings` is not
installed on this box, nor vendored in the repo. Neither are `tinycss2` or
`html5lib`.

Writing a `mimic_codecs` without that scoping means guessing at which of
`codecs`' surface matters, which is how a shim ends up quietly approximating —
the exact thing `devdocs/dev/python-compat-tiers.md` forbids for T1 shims.

Blocked on [[decide-may-agents-fetch-thirdparty-sources-as-oracles]], which is
the same wall [[feature-lib-reportlab-fidelity-vs-oracle]] hit: a differential
or scoped-against-real-usage ticket needs the real thing present, and putting it
there is the user's call, not an agent's.

## UNBLOCKED and SCOPED 2026-08-09 (Track B) — against the real sources

The sources are fetchable now (`install_lib_candidates.sh nilpy-stack`), so this
ticket's own instruction — scope against the real usage before writing anything
— could finally be followed. Measured against the pinned compiler at
`0250202db`.

### `codecs` is the keystone of the whole stack

`webencodings/__init__.py` is blocked by **exactly one thing**, `import codecs`.
Everything else in that package already compiles (`labels.py` OK; `mklabels.py`
is a dev script wanting `urllib_request`; `tests.py` is tests). And
webencodings is the bottom of the stack — six tinycss2/html5lib files then wall
on `import webencodings`.

### The measured surface — smaller than the ticket guessed, in one direction

In `__init__.py`, the ONLY use is:

```python
codec_info = codecs.lookup(python_name)          # line 85
... encoding.codec_info.decode(input, errors)[0]  # 158
... encoding.codec_info.encode(input, errors)[0]  # 183
... encoding.codec_info.incrementaldecoder(errors).decode   # 317
... encoding.codec_info.incrementalencoder(errors).encode   # 342
```

The object-returning shape works in NilPy today — verified: a module function
returning an instance whose attributes are then read compiles and runs. So no
frontend work is needed for the shim's SHAPE.

Elsewhere, and NOT needed for `__init__.py`:
- `html5lib/_inputstream.py` wants only the BOM CONSTANTS (`BOM_UTF8`,
  `BOM_UTF16_LE/BE`, `BOM_UTF32_LE/BE`) — byte strings, trivial.
- `html5lib/serializer.py` wants `register_error` / `xmlcharrefreplace_errors`.
- `webencodings/x_user_defined.py` subclasses `codecs.Codec` /
  `IncrementalEncoder` / `StreamReader`. **That one is blocked** — a QUALIFIED
  base class fails: `class C(math.Foo)` -> "unknown base class Foo". It is only
  reached for the legacy `x-user-defined` encoding, via a lazy import inside a
  branch, so it does not block `__init__.py`.

### The real cost is the ENCODINGS, and it must not be faked

`labels.py` maps to **41 distinct python encoding names** — including `big5`,
`gb18030`, `euc-jp`, `euc-kr`, `iso-2022-jp`, `shift_jis`. A `lookup()` that
returned a plausible-but-wrong codec for those is exactly the silent-wrong-output
failure this project treats as worst, and `python-compat-tiers.md` forbids it for
a T1 shim.

**Proposed scope, which is the next session's job:** implement `lookup()` for the
encodings that can be done CORRECTLY — utf-8, ascii, latin-1/iso-8859-1, the
other single-byte iso-8859-* (simple tables), utf-16le/be, utf-32le/be — plus
the incremental decoder/encoder shapes and the BOM constants, and **raise by
name** for every other label. utf-8 covers the overwhelming majority of real
input; the rest refuse loudly instead of guessing. State the subset in the unit
header, as `mimic_reportlab_pdfgen` does.

### Gate (updated)

`make lib-test`, plus `webencodings/__init__.py` compiling, plus a `.npy`
round-tripping utf-8 and utf-16 against CPython's own `codecs` output, plus a
refused label producing an error rather than wrong bytes.

## BLOCKED 2026-08-09 — the builtins it would delegate to are wrong

Before writing `lookup()`, the obvious question: what do the existing
`str.encode` / `bytes.decode` do? Measured against CPython:

    "hé".encode("latin-1")   pxx 3 bytes (UTF-8)   CPython 2 bytes
    "hé".encode("utf-16le")  pxx 3 bytes (UTF-8)   CPython 4 bytes
    "hé".encode("ascii")     pxx succeeds          CPython UnicodeEncodeError
    b.decode("latin-1")      pxx 'h\ufffd'         CPython 'hé'
    b.decode("utf-8")        pxx 'h\ufffd'         CPython UnicodeDecodeError

**The encoding argument is ignored in both directions** — always UTF-8, never
raising. Filed as
[[bug-n-str-encode-and-bytes-decode-ignore-the-encoding]] (prio 60: it is a
silent-wrong-bytes bug in its own right, quite apart from this ticket).

So a `codecs.lookup(name)` whose `.encode`/`.decode` delegated to the builtins
would hand webencodings a wrong answer for every non-UTF-8 label while appearing
to work — the approximation `python-compat-tiers.md` forbids. And implementing
the encodings a second time INSIDE the shim, while `str.encode` stays wrong,
would be two mechanisms for one concept that can disagree.

The order is therefore: fix the builtins to honour their argument (and raise for
what they cannot do), then `lookup()` is a thin delegation and this ticket is
small again. The scope proposed above — which encodings to do correctly and
which to refuse by name — applies to the BUILTINS now; it moved down a layer.

