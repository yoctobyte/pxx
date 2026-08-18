---
track: B
prio: 30
type: feature
blocked-by: []
summary: "lib/rtl/mimic_urllib_request.py currently REFUSES: it makes importing code compile and raises NotImplementedError on any call. The client it needs ALREADY EXISTS — lib/rtl/http.pas, gated by make lib-test as http + redirect + keepalive + pool + gzip + cookie + json, over the TLS seam. So this is not an HTTP project, it is a Python face on an existing unit, in the shape mimic_codecs.pas already demonstrates (a .pas shim reached from NilPy). The one corpus caller is a code generator, so no library file is blocked on it."
status: done
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


## Resolution (2026-08-18, frank3-b)

Landed as `lib/rtl/mimic_urllib_request.pas` + `lib/rtl/mimic_urllib_error.pas`,
replacing the refusing `.py`. Measured on the pin
(`stable_linux_amd64/default/pinned`, v352) at HEAD `df15ae3fe`.

### The premise held

The refusing shim was verified to still refuse before any code was written
(`urlopen` raising NotImplementedError on the pin), and `lib/rtl/http.pas` was
verified to be reachable with **no `-Fu`** — so the corrected scope in this
ticket was right and the work was hours, not a project.

### The language question this ticket left open, settled

**`.pas`, not `.py`.** http.pas answers with RECORDS (`THttpResponse`), which a
NilPy `.py` shim cannot receive; turning one into a Python object is the shim's
whole job. A prototype confirmed the seam carries everything needed before the
real unit was written: a Pascal class reached through the `mimic_` resolver
supports `with` (`__enter__`/`__exit__`), returns `bytes` that `.decode()`, and
raises exceptions NilPy catches by name.

### What landed

- **`mimic_urllib_error.pas`** — `URLError`, `HTTPError`, `ContentTooShortError`.
  CPython's whole `urllib.error`, so complete rather than a subset. Declared
  once HERE and ALIASED into `urllib.request`, so `except HTTPError` catches the
  same class through either import — verified (`HTTPError is HE2` → True).
- **`mimic_urllib_request.pas`** — `urlopen` over `HttpExec` with redirect
  following (incl. the 303/302-after-POST rewrite to GET) and the
  raise-outside-2xx rule; `HTTPResponse` (read/readline/readlines, the three
  status spellings, geturl/getcode/info, `with`); `HTTPMessage` (case-insensitive
  get, `get_all` for repeated headers, get_content_type); `Request`; `urlretrieve`.

### The error mapping this ticket asked us to decide

CPython's split, kept: **`HTTPError`** when a response ARRIVED with a status
outside 2xx (it carries the body, so `e.read()` works), **`URLError`** when none
did. Both descend from `OSError` as CPython's do, so `except OSError` around
urlopen — which real code writes — still catches. No Pascal exception escapes:
every refusal and transport failure is a `URLError`.

### Refusals, in the ticket's own spirit of "refuse loudly over approximate"

`timeout=` (http.pas has NO timeout — accepting and ignoring it would turn a
bounded wait into an unbounded one), https with no TLS backend registered (names
the two the RTL ships rather than picking one), non-http(s) schemes,
`urlretrieve` with no filename, and the opener/handler machinery (absent, so a
compile error rather than an object that ignores its handlers).

### Gate

`make lib-test` **green** (exit 0, "against stable v352"), including the new
`mimic_urllib_request matches CPython` line and 8/8 refusals.

The client test is diffed against CPython **line for line**, with both clients
pointed at the SAME local server (`test/lib_mimic_urllib_request_server.pas`) —
which is what makes it a comparison against the real urllib rather than against
our own idea of what a server says. 58 lines, byte-identical.

**The oracle earned its keep — four defects it caught that reasoning had not:**

1. `urlopen(req)` **clobbered the Request's own data** and POSTed the body `0`.
   An omitted `Variant` argument arrives as the integer 0, NOT as None, so
   `data <> pynone` was true for an omitted argument. A wrong value that reached
   the server and came back looking plausible.
2. `get_type()`/`get_host()`/`get_selector()` **do not exist** in current
   CPython — they were written from memory, and the oracle has attributes
   `.type`/`.host`/`.selector` instead.
3. `origin_req_host` drops the `:port`; `.host` keeps it. They are not the same
   string.
4. `has_header`/`get_header`/`remove_header` take the key **verbatim** — only
   `add_header` capitalises. Folding on both sides looks tidier and is a
   different function from CPython's.

Also corrected against the oracle: `ContentTooShortError` inherits URLError's
bracketed `str`, and `Request("http://h").selector` is `''`, not `'/'`.

### The ticket's named corpus caller now runs

`webencodings/mklabels.py` compiles AND runs end to end against a local
endpoint, producing output identical to CPython's **except one line** — and that
line is a separate frontend bug, filed below, with `urlopen` not involved.

### Filed, not fixed (Track B owns the tool, never the bug)

- [[bug-n-backslash-newline-in-a-string-literal-is-not-a-line-continuation]] —
  `\` + newline inside a string literal is emitted literally. Silent wrong
  value; the mklabels generator emits a file with a stray `\` line, which would
  be a syntax error in the file it generates. **p45.**
- [[bug-p-a-parameterless-function-is-undefined-as-a-method-call-argument]] —
  `k.m(zero)` fails with `undefined variable (zero)` while `free(zero)` on the
  line above compiles. Shaped this unit's code. **p35.**
- [[bug-n-str-of-a-pascal-declared-exception-ignores-str-when-caught-as-a-base]]
  — `str(e)` dispatches `__str__` by the static type of the except clause, so
  `except Exception as e` loses the message. **p40.**

### One diagnosis that was wrong and is recorded so it is not re-derived

A Pascal-declared exception subclass appearing not to stringify was first read
as a compiler bug. It is not: `uses pylib, sysutils` makes a bare `Exception`
resolve to **sysutils'** sibling class, so the subclass lands outside pylib's
tree. That is the documented design, and `mimic_urllib_error.pas` sidesteps it
by descending from `OSError`, which only pylib declares. The separate, real bug
is the static-dispatch one filed above — the two look identical from NilPy.

### Known limits, stated rather than hidden

- The body is fully buffered before `read()` sees it (http.pas reads a whole
  response), so `read(8192)` in a loop does not stream.
- `add_unredirected_header` survives a redirect hop here; CPython drops it.
- The https path is gated only by `TlsAvailable`; the TLS seam itself is covered
  by http.pas's own suite, not by this one.

## Log
- 2026-08-18 — resolved, commit PENDING-COMMIT.
