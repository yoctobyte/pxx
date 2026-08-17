---
track: B
prio: 45
type: feature
blocked-by: []
owner: frank3
status: done
---

# `mimic_six` and `mimic_warnings` — the biggest lever for the library campaign

Measured 2026-08-09 by compiling all 48 `.py` files of `webencodings`,
`tinycss2` and `html5lib` as source and ranking what stopped each one. After the
language walls were fixed (backslash continuations, relative imports,
`class C(object)`), **every remaining failure is a missing module**, and the
distribution is lopsided:

| missing module | files blocked |
| --- | --- |
| **`six`** | **11** |
| `xml.dom` / `xml.sax` | 5 |
| **`warnings`** | **3** |
| `genshi` (an optional treewalker) | 2 |
| `codecs` | 2 |

## Why `six` is the cheap win

`six` is a pure-Python Python-2/3 compatibility shim, and on a Python-3-only
dialect almost every one of its names is trivially true:

- `PY2 = False`, `PY3 = True`
- `text_type = str`, `binary_type = bytes`, `string_types = (str,)`
- `integer_types = (int,)`, `class_types`, `unichr = chr`
- `iteritems(d)` → `d.items()`, `itervalues`, `iterkeys`
- `with_metaclass` / `add_metaclass` — the two that are NOT trivial

The last pair is the honest caveat: they are metaclass machinery, which NilPy
does not have. Real usage in html5lib should be checked before deciding whether
to implement them, alias them to a no-op, or **refuse them by name** — the last
being much better than a silently wrong class, and consistent with how the rest
of the dialect walls unsupported features.

`warnings` is smaller still: `warn(msg)` printing to stderr and
`simplefilter`/`catch_warnings` as no-ops covers what a library does with it.

## Note on how the file counts read

A file is rejected at its FIRST unavailable import, so one missing module hides
however many gaps sit behind it. These counts are therefore a lower bound on the
unblock, not an estimate of the remaining work — landing `six` will reveal the
next layer, which is the point of doing it.

## Gate

`make lib-test`, plus re-running the 48-file scan and recording the new counts
on `feature-nilpy-thirdparty-libraries-as-targets` (the scan is a few lines of
shell; the ranked-walls table there is the format to update).

## Measured surface, 2026-08-09 — every `six` name html5lib/tinycss2 actually import

Not a guess at `six`'s API: this is `grep "from six" ` over the real sources, so
the shim can be scoped to exactly this and nothing else.

| name | import sites | what it is on Python 3 |
| --- | --- | --- |
| `text_type` | **8** | `str` |
| `PY3` | 2 | `True` |
| `binary_type` | 1 | `bytes` |
| `string_types` | 1 | `(str,)` |
| `unichr` | 1 | `chr` (imported as `from six import unichr as chr`) |
| `viewkeys` | 1 | `d.keys()` |
| `with_metaclass` | 1 | **metaclass machinery — the hard one** |

Plus three sites importing from **`six.moves`**, which is a different problem:
`urllib_parse` (sanitizer), `http_client` and `urllib` (`_inputstream`). Those
are stdlib re-exports, so they need `urllib`/`http.client` to exist at all — not
part of this shim.

**So the split is 12 trivial import sites against 2 hard ones.** Six of the
seven names above are one-line aliases; `with_metaclass` appears exactly once,
in `html5parser.py`. That single file is what decides whether the shim gets
html5lib's parser or only its periphery — worth looking at `html5parser.py`'s
use of it before choosing between implementing, no-opping, and REFUSING by name.

`viewkeys` is a small trap worth naming: it is a FUNCTION (`viewkeys(d)`), not a
method, so aliasing it to `dict.keys` needs the unbound-method-as-a-value
support that `feature-nilpy-str-surface-gaps-2026-08-09` records as missing
(`sorted(xs, key=str.lower)` fails the same way). A one-line `def viewkeys(d):
return d.keys()` sidesteps that entirely.

## MEASURED 2026-08-09, Track B: the premise does not hold yet

Before writing a line of the shim, the aliasing idiom it is built on was
compiled. It does not:

    text_type = str          ->  pascal26:1: error: unexpected token
    string_types = (str,)    ->  pascal26:1: error: unexpected token
    unichr = chr             ->  pascal26:1: error: undefined variable (chr)

A type name is not a first-class value in NilPy — filed with the full boundary
as [[bug-n-a-type-name-is-not-a-first-class-value]] (functions ARE values;
`f = len` and a user `def` both work, and a user-class alias `A = B` parses but
is then unusable, which is worse).

That re-scores this ticket rather than blocking all of it:

| name | sites | writable today? |
| --- | --- | --- |
| `text_type` | 8 | **no** — needs `str` as a value |
| `PY3` | 2 | yes, `PY3 = True` |
| `binary_type` | 1 | **no** — needs `bytes` as a value |
| `string_types` | 1 | **no** — needs a tuple of types |
| `unichr` | 1 | yes, as `def unichr(i): return chr(i)` |
| `viewkeys` | 1 | yes, as `def viewkeys(d): return d.keys()` |
| `with_metaclass` | 1 | the separate hard one (metaclasses) |

So **10 of the 13 import sites are blocked**, and the three writable ones are
the periphery. A shim shipped now would resolve `import six` and then fail at
the first `text_type`, which is a worse experience than the honest missing
module — and it would violate the T1 rule in
`devdocs/dev/python-compat-tiers.md` that a shim states its subset and fails
loudly rather than approximating.

`warnings` is unaffected by any of this and is still a small, self-contained
win: `warn(msg)` to stderr, `simplefilter`/`catch_warnings` as no-ops.

Blocked on the N ticket for the `six` half; the `warnings` half can go first.

## 2026-08-09, second measurement: the `warnings` half is blocked TOO

The note above said "`warnings` is unaffected by any of this and is still a
small, self-contained win". Measured against the real html5lib sources, that is
wrong.

In non-test html5lib code every call is `warnings.warn(msg, SomeWarningClass)` —
16 of them — and passing a class as an argument is precisely the blocked
pattern:

```
error: Nil Python: the class W cannot be used as a VALUE yet (stored in a
variable, list or dict, or passed as an argument) — only construction W(...),
isinstance(x, W) and `except W:` are supported.
```

So a `mimic_warnings` would resolve `import warnings` and then fail one line
later at the first `warn(msg, Category)` — worse than the honest missing module,
and against the T1 rule.

`simplefilter` / `catch_warnings` / `resetwarnings` appear ONLY in html5lib's
test files, which the campaign scan excludes, so they are not a reason to write
the shim either.

**Both halves of this ticket now wait on the same thing** —
[[bug-n-a-type-name-is-not-a-first-class-value]] and its user-class sibling.
Nothing here is worth writing until a class can be passed as a value.


## 2026-08-14 (claude-A-N) — UNBLOCKED. The language half is done; measured against the real six.py

`bug-n-a-type-name-is-not-a-first-class-value` is resolved, so the frontmatter
blocker is cleared. Every line this ticket called load-bearing now compiles and
answers correctly:

    text_type = str            binary_type = bytes
    string_types = (str,)      integer_types = (int,)
    class_types = (type,)      isinstance(s, string_types)

`type` as a value was the last piece and landed with pin v288.

**Then measured rather than assumed:** compiled pip's vendored `six.py` (998
lines) with the compiler at HEAD. It no longer stops on anything about types —
it stops at **line 25, `import functools`**, which is precisely the shim work
this ticket is for. `itertools` and `operator` are the two imports behind it.

So the remaining job here is what the title says and nothing more: write the
shims. Nothing in Track N blocks it now.

## 2026-08-17 (frank3, Track B) — re-measured on v344. The two halves have DIFFERENT blockers now.

Premises re-checked before writing a line, because this ticket's premises have
been wrong twice already. Against `pinned` **v344**.

### The `six` half: every language prerequisite now holds

```python
text_type = str          binary_type = bytes
string_types = (str,)    integer_types = (int,)
class_types = (type,)    isinstance("a", string_types)   # True, matches CPython
```

All compile and answer correctly, as does passing a plain class as an argument.
The 2026-08-14 note is confirmed on this pin, not just the one it was written on.

### The `warnings` half is blocked again — on a NEW thing, not the old one

The old blocker (a class cannot be passed as a value) is **gone**: `warn("m", W)`
for a user class `W` compiles and runs. But measured against the real html5lib
sources rather than assumed:

| category passed to `warnings.warn` | non-test sites |
| --- | --- |
| `DataLossWarning` | **14** |
| `DeprecationWarning` | 2 |

and `html5lib/constants.py:2940` is `class DataLossWarning(UserWarning):`.

**`Warning`, `UserWarning` and `DeprecationWarning` do not exist in NilPy.**

```
print(Warning, UserWarning, DeprecationWarning)
  -> pascal26: error, near: print  Warning >>>  UserWarning
```

CPython prints all three — they are builtins, not members of the `warnings`
module, so a `mimic_warnings` **cannot supply them**: the calling code names them
bare. All 16 sites need them (14 to define `DataLossWarning`, 2 directly).

Filed as [[bug-n-the-builtin-warning-exception-hierarchy-is-missing]]. Until it
lands, a `mimic_warnings` would resolve `import warnings` and then fail at the
first category — worse than the honest missing module, and against the T1 rule
in `devdocs/dev/python-compat-tiers.md`. **The `warnings` half is parked, again
for a measured reason rather than a guessed one.**

### The `six` half is blocked on a DESIGN fork, not a defect

Writing it revealed that the ticket's title assumes a mechanism that does not fit
the content. `six` is a file of Python-level aliases — `text_type = str`,
`string_types = (str,)` — and the shim slot the title names is **Pascal only**:
`parser.inc:33210` probes `lib/pcl/mimic_<name>.pas` then `lib/rtl/mimic_<name>.pas`,
and nothing else. Expressing "the `str` type object, as a value" from Pascal is
not something any existing shim does.

Measured that the alternative works: a NilPy `.py` module in a library root
(`feature-nilpy-import-a-py-module-from-the-library-path`, resolved at
`parser.inc:33845`) serves it exactly, byte-for-byte with CPython:

```
from six import text_type, PY3, binary_type, unichr, viewkeys
print(text_type("x"), PY3, unichr(65), sorted(viewkeys({"a": 1})))
  pxx:     x True A ['a']
  CPython: x True A ['a']
```

**But that route silently defeats `--no-shims`.** That flag exists so "a build
that succeeds provably used no compatibility shim" (`defs.inc:1571`), and it
refuses only the `mimic_` substitution. A `lib/**/six.py` is a real library
module by the resolver's rules, so it would satisfy `import six` under
`--no-shims` and quietly falsify exactly the guarantee the flag sells.

Not guessing between those. Filed as
[[decide-how-python-shaped-shims-should-be-shipped]] with the three options and
a recommendation; parking this in `unfinished/` rather than shipping a mechanism
that might have to be unpicked.

**Nothing here is a defect in the `six` content** — the name list, its scoping to
what html5lib/tinycss2 actually import, and the `viewkeys`-is-a-function trap
are all still correct and still the work. Only *where the file goes* is open.

## 2026-08-17 (frank3, later) — the `six` half is LANDED. Measured on v345.

The mechanism fork this ticket was parked on is settled: the shim slot now
probes `mimic_<name>.py` (Track A, `42ab5131e`), which is the option this
ticket's `decide-` recommended, so the file lives in the shim namespace and is
refusable. Verified rather than assumed:

```
import six          (no shim)  -> error: no unit named six and no shim mimic_six
import six          (shim)     -> note: six -> mimic_six (shim, subset)
import six --no-shims          -> error: ... (--no-shims refuses the mimic_ substitution)
```

So `--no-shims` still means what it says. That was the whole content of
[[decide-how-python-shaped-shims-should-be-shipped]].

### What landed

`lib/rtl/mimic_six.py`, scoped to the surface the corpora actually import
(re-grepped on v345 across webencodings + html5lib + tinycss2, non-test):
`text_type` x11, `unichr` x4, `PY3`/`PY2` x4, `binary_type`, `string_types`,
`viewkeys`, `with_metaclass`, plus the one-line siblings (`integer_types`,
`class_types`, `iterkeys`/`itervalues`/`iteritems`, `viewvalues`/`viewitems`,
`MAXSIZE`).

`test/lib_mimic_six.npy` is in `make lib-test` — and is a **differential, not a
spec**: the same `.npy` runs under CPython against the REAL `six`, and the two
outputs are byte-identical. An alias table's failure mode is a plausible wrong
entry, which a hand-typed expectation would simply encode twice.

### Two judgement calls, both measured first

**`viewkeys` returns a `set`, not a keys view.** Its only corpus use is set
algebra (`viewkeys(a) & viewkeys(b)`, html5parser.py:2779). Measured: two
`.keys()` results come back as lists here and `list & list` is a TypeError,
while `set & set` works. What that gives up is liveness; no corpus site holds a
view across a mutation, and returning the faithful-but-unusable thing would fail
at the `&`.

**`with_metaclass` refuses rather than returning `object`** — see below.

### The count did NOT move, and that is the predicted outcome

| | files compiling |
| --- | --- |
| without `mimic_six` | 4 / 48 |
| with `mimic_six` | 4 / 48 |

But **13 files had `six` as their FIRST wall, and now 0 do.** This ticket's own
"Note on how the file counts read" called it exactly: a file is rejected at its
first unavailable import, so the counts are a lower bound on the unblock and
landing `six` reveals the next layer. It did.

The next layer, measured (first error per file, non-test, 48 files):

| wall | files |
| --- | --- |
| `webencodings` (a sibling corpus package, not a shim) | 6 |
| `undefined variable` | 5 |
| `xml.dom` | 4 |
| `constants` (html5lib's own module — sibling resolution) | 4 |
| class-inherits-from-itself | 3 |
| **`warnings`** | 3 |
| `six.moves` | 3 |
| `xml.sax.xmlreader` | 2 |
| `genshi` | 2 |
| `bisect` | 2 |

`six` does not appear at all. The two biggest remaining items are **package/
sibling resolution** (`webencodings`, `constants`, `_utils` — 11 files between
them), not missing shims.

### `six.moves` is deliberately absent

Three sites want `http_client`, `urllib`, `urllib_parse` from it. Those are
stdlib re-exports needing `urllib` and `http.client` to exist — a different job
with a different blocker, and faking them is exactly the T1 violation this
ticket warned about.

### The `warnings` half is UNCHANGED and still blocked

Re-measured on v345: `Warning` / `UserWarning` / `DeprecationWarning` still do
not exist, and 14 of html5lib's 16 non-test `warnings.warn` sites need
`UserWarning` merely to declare `DataLossWarning`. Still
[[bug-n-the-builtin-warning-exception-hierarchy-is-missing]], still not
something a `mimic_warnings` can supply, since calling code names them bare.

### New blocker found for `with_metaclass`, and it is smaller than expected

`class Phase(with_metaclass(...))` does not compile because **a class base that
is an expression does not compile** — `B = object; class P(B)` fails where
`class P(object)` and `class P(SomeClass)` work. Filed as
[[bug-n-a-class-base-that-is-an-expression-does-not-compile]].

The good news is in that ticket: html5lib's `getMetaclass` returns plain `type`
unless its debug flag is set, so the real path asks for **no metaclass at all**.
Supporting `with_metaclass` therefore does not need metaclasses, only base-
expression evaluation. `mimic_six` refuses it with a message naming that ticket
rather than returning `object`, because `object` would be semantically right and
*still* would not compile at the call site.

**Ticket stays in `unfinished/`**: the `six` half is done, the `warnings` half is
blocked on the builtin hierarchy.

## 2026-08-17 (frank3, third pass) — the `warnings` half is LANDED. Ticket closes.

Its blocker, [[bug-n-the-builtin-warning-exception-hierarchy-is-missing]], was
fixed and pinned (**v346**) — the categories now reach `PXX_STABLE`, verified
before anything was written.

### Scope, re-measured on v346

Across html5lib + tinycss2 + webencodings, **non-test** code imports `warnings`
in exactly three files and calls exactly one thing: `warnings.warn(msg, Category)`,
16 times. `simplefilter` / `catch_warnings` / `resetwarnings` appear **only** in
those projects' own test suites.

That corrects my own count from earlier today, which reported 3 `simplefilter`,
2 `catch_warnings` and 1 `resetwarnings` in non-test code. Wrong: the `grep -h`
that produced it suppressed filenames, so the `grep -v /tests/` filtering the
paths had nothing left to match on. The earlier 2026-08-09 note ("they appear
ONLY in html5lib's test files") was right and I contradicted it with a bad
measurement.

They are implemented anyway — a few lines each, and a library that calls one
should not die on an AttributeError — but nothing in the measured corpus
exercises them, and the file says so.

### What landed

`lib/rtl/mimic_warnings.py` + `test/lib_mimic_warnings.npy` in `make lib-test`.

**The test asserts stdout ONLY**, and that is the honest choice rather than a
gap: stderr is exactly where the two implementations differ on purpose. CPython
prints `<file>:<line>: <Category>: <message>` plus the offending source line
because it walks the call stack; there is no frame introspection here, so this
prints `<Category>: <message>`. Asserting stderr would either encode our format
as though it were CPython's, or fail for a documented divergence. The test runs
unmodified under CPython and the stdout is byte-identical.

Two divergences, both measured before choosing:

- **No source location** (above).
- **Dedupe by (category, message), not by location.** Measured: CPython's
  default filter reports once per call site — a `warn()` in a three-iteration
  loop prints once. Without a location the text is the closest analogue. It
  matches CPython for the common case and differs when one message is warned
  from two places (CPython twice, this once). Printing every time was the
  alternative and is *further* from CPython, not closer: it turns a loop into a
  flood.

`catch_warnings(record=True)` **refuses** rather than returning an empty list —
an empty list reads as "no warnings were raised" in exactly the place a caller
is asserting on it.

### A silent segfault found on the way

The natural signature is `warn(message, category=UserWarning)`. That **segfaults
the moment the default is taken** — exit 139, no diagnostic, no output. Any type
as a default parameter value does it: user class, builtin type, builtin
exception, and merely reading `.__name__` off it is enough. Passing the argument
explicitly is fine, so the fault is in materialising the default.

Filed as
[[bug-n-a-type-as-a-default-parameter-value-segfaults-when-the-default-is-taken]]
(N, p60 — it is silent, and it breaks NilPy's upward-compatibility contract,
since `warnings.warn("x")` is ordinary working CPython).

The shim takes `category=None` and substitutes, **registered in
`devdocs/dev/track-b-workarounds.md`** with a revert-to note per the Track B
convention — the sanctioned way to sidestep an open compiler bug without hiding
it. The test's `warn("no category given")` line is that workaround's regression
guard.

### Corpus effect: same shape as `six`

`warnings` is no longer the first wall on any of the three files that import it.
They now stop on `undefined variable (digits)` (`_ihatexml.py`),
`xml.sax.saxutils` (`sanitizer.py`) and `constants` (`etree_lxml.py`) — i.e. the
next layer, of which the biggest item remains package/sibling resolution.

### Both halves are done — resolving.

`six` landed earlier today (`c061ece2b`), `warnings` here. `six.moves` stays
deliberately absent: stdlib re-exports needing `urllib`/`http.client`, a
different job with a different blocker.

`make lib-test` green against stable **v346**.

## Log
- 2026-08-17 — resolved, commit eb29fa2a3.
