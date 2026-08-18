---
track: B
prio: 30
type: feature
blocked-by: []
summary: "lib/rtl/mimic_urllib_request.py currently REFUSES: it makes importing code compile and raises NotImplementedError on any call. The client it needs ALREADY EXISTS — lib/rtl/http.pas, gated by make lib-test as http + redirect + keepalive + pool + gzip + cookie + json, over the TLS seam. So this is not an HTTP project, it is a Python face on an existing unit, in the shape mimic_codecs.pas already demonstrates (a .pas shim reached from NilPy). The one corpus caller is a code generator, so no library file is blocked on it."
---

# A real `urlopen` for `mimic_urllib_request`, over the RTL's own stack

- **Type:** feature (library) — **Track B**.
- **Filed:** 2026-08-18 by frank3-fc, from
  [[feature-b-module-shims-for-the-html5lib-corpus]].

## Where it stands

`lib/rtl/mimic_urllib_request.py` exists and refuses. `urlopen` and
`urlretrieve` raise `NotImplementedError` naming this ticket; `Request` is real
(it only holds what it was handed). That was the deliberate call: the module
being ABSENT made importing code stop at `no unit named urllib_request`, which
says nothing about why, and the same-shaped decision is already precedent in
`mimic_six.with_metaclass`.

## Corrected scope: the client already exists

The first draft of this ticket said "an HTTP client is not a shim, it is a
project". That was wrong, and worth recording because it would have mis-ranked
the work by an order of magnitude. **`lib/rtl/http.pas` is already there**, and
`make lib-test` gates it as `http + http-async + http-redirect +
http-keepalive + http-pool + http-pool-concurrent + http-gzip + http-cookie +
http-serve + http-json`, with https over the TLS seam. Redirects, keep-alive,
gzip and cookies are done.

So what is left is the FACE, not the client:

- map `urlopen(url)` onto `http.pas`'s request call,
- a response object with the file-like surface callers hold (`read`, `status`,
  `headers`, and use as a context manager),
- `Request` (already real here) carried through, including method and headers,
- decide the error mapping — CPython raises `HTTPError`/`URLError`, and a
  caller that catches those must not meet a Pascal exception instead.

Shape precedent: `lib/rtl/mimic_codecs.pas` is a `.pas` shim reached from
NilPy, so this can be `mimic_urllib_request.pas` over `http.pas` rather than
Python-side reimplementation. If it stays `.py`, it needs whatever binding
`http.pas` exposes to NilPy — check that first, since it decides the language.

## Why it is p25 and not higher

The only corpus caller is `webencodings/mklabels.py`, a code GENERATOR: it
downloads the WHATWG encodings index and prints the `labels.py` that
webencodings ships pre-generated and checked in. The library itself never
fetches anything. So this unblocks **zero library files** — it buys the ability
to run one generator, plus a genuinely useful RTL capability for apps.

Rank it up when an app or example wants `urlopen` specifically — Pascal callers
already have `http.pas` and need nothing from this. p30 rather than p25 only
because the corrected scope is hours, not a project.
