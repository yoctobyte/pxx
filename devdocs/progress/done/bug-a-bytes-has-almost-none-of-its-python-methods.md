---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`bytes` carries decode/find/endswith/hex/count and essentially nothing else; `float` carries NONE of its methods at all — no lower, upper, startswith, split, strip, replace, join, translate, index. `b.lower()` is what stops webencodings, and every one of these is reachable from ordinary CPython code that has no reason to expect a gap."
status: done
owner: claude-A-N-nightly
---

# `bytes` is missing almost all of its Python methods

Found compiling `webencodings/__init__.py` for
[[feature-b-mimic-codecs-for-nilpy]], against
`stable_linux_amd64/default/pinned` **v339 /
f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c**.

## What stops the library, exactly

```python
def ascii_lower(string):
    # This turns out to be faster than unicode.translate()
    return string.encode('utf8').lower().decode('utf8')
```

```
error: Nil Python: TPyBytes has no method lower
```

That function is `webencodings`'s label normaliser — every `lookup()` goes
through it — so the package cannot work without it.

## The measured surface

`hasattr` over a `bytes` value on the pinned binary:

| method | present |
| --- | --- |
| `count` | yes |
| `decode`, `find`, `endswith`, `hex` | yes (from the class declaration) |
| `lower`, `upper`, `title` | **no** |
| `startswith` | **no** — while `endswith` IS there |
| `split`, `join`, `strip`, `lstrip`, `rstrip` | **no** |
| `replace`, `translate`, `index`, `isdigit` | **no** |

`startswith` missing while `endswith` is present is the tell that this grew
one method at a time as something needed it, rather than from the type's
contract. `webencodings._detect_bom` needs `startswith` on the very next line
after `lower`.

## Where

`TPyBytes` in `compiler/builtin/pylib.pas` (Track A file ownership — this is
compiler/builtin, not lib/**). The class already has `at`/`put`/`count`/
`extend`, so the methods are all short: they are byte-wise loops over `FData`,
and `lower`/`upper` are ASCII-only in CPython too (`b'\xc3\xa9'.lower()` is
unchanged), which removes the only part that could have been subtle.

## Do it as a set, not as one method

Per `normalise-dont-special-case.md`: adding `lower` alone leaves the next
caller to file the next ticket, and the asymmetric `endswith`-without-
`startswith` above is what that policy already produced. The whole ASCII-shaped
group — case, strip/split/join, replace/translate, startswith/index — is one
afternoon and closes the class.

A `bytes` method that CPython defines and pxx omits is a hard compile error, so
this failure mode is at least loud. It is still a wall in front of every
byte-handling Python library, which is most of the parsing ones.


## The same hole in `float`, measured at the same time

Checked because the pattern looked type-wide rather than bytes-specific, and it
is. `hasattr` on a `float`, same binary:

```
hex False   is_integer False   as_integer_ratio False
fromhex False   conjugate False   real False   imag False
```

Not one of them. `x.is_integer()` in particular is ordinary, idiomatic modern
Python and is what a library reaches for instead of `x == int(x)`.

Kept on this ticket rather than split: it is the same statement (a builtin
scalar type carrying an ad-hoc subset of its Python methods) about a second
type, and whoever fixes one is a grep away from the other. `float`'s are even
smaller than `bytes`'s — `is_integer`, `hex`/`fromhex`, `as_integer_ratio`, and
`real`/`imag`/`conjugate` are trivia on a double.

## Resolution (2026-08-15) — both halves, in two commits

### `bytes`

Added as a SET, per this ticket: case (`lower`/`upper`/`title`/`capitalize`/
`swapcase`), `strip`/`lstrip`/`rstrip` in BOTH the whitespace and
character-set forms, `split`/`rsplit`/`splitlines`/`join`, `replace`,
`translate`, `startswith`, `index`/`rfind`/`rindex`, and
`isdigit`/`isalpha`/`isalnum`/`isspace`/`isupper`/`islower`.

Two rules that were worth stating once rather than fifteen times, and are:

- ASCII-only exactly where CPython is ASCII-only. `b'\xc3\xa9'.lower()` is
  unchanged in CPython too — a bytes object has no encoding to case-map
  through — which removes the only part that could have been subtle.
- Every buffer-BUILDING method carries `FIsByteArray` across (`PyBytesLike` is
  the one constructor they all go through), or `bytearray(...).lower()`
  silently becomes a `bytes`. Same rule `pybytes_slice` already states.

### `float`

`is_integer`, `hex`, `as_integer_ratio`, `conjugate` — the four callables.
`hex` is exact (13 hex digits IS a double's mantissa, which is the point of
the format) including the infinities, NaN, ±0 and the subnormals;
`as_integer_ratio` is exact over the whole 64-bit range and RAISES outside it
rather than answering a truncated pair (recorded in
`devdocs/dev/nilpy-semantics-divergences.md`, since NilPy ints are 64-bit and
CPython's are not — it goes away for free if that ever changes).

**The interesting decision:** the float names are claimed only at the two
intercept sites that KNOW the receiver's static type, and deliberately NOT in
`PyIsIntMethodName`. That test feeds `PyIsIntMethodSuffixAhead`, which sees a
NAME and no receiver — and `hex` is already a method of `bytes`. A name-only
claim would make every generic postfix chain step aside for `b.hex()` and hand
it to an int intrinsic that cannot serve it. The price is that a grouped
`(3.5).hex()` takes the ordinary path, which is worth it.

### Oracle

Both tests' expected output is CPython 3's on the same source, diffed rather
than reasoned about, and the surprising cases are kept deliberately:
`b"they're".title()` is `b"They'Re"`, `b"aaa".replace(b"aa", b"a")` is `b"aa"`,
`b"".split(b",")` is `[b'']` while `b"".split()` is `[]`, `b"123".isupper()` is
False, `(2.0).hex()` keeps all thirteen digits.

Tests: `test/test_nilpy_bytes_methods.npy` and
`test/test_nilpy_float_methods.npy` (+ `.expected`), wired into `test-nilpy`
and `test-core`.

Gate: `tools/gate.sh quick` GREEN. A pylib change moves no compiler binary
(the compiler does not `use` pylib), so no re-pin is a gate requirement.

### Left open, filed

[[bug-nilpy-float-methods-are-invisible-to-the-runtime-dispatcher]] — the four
float methods reach a STATICALLY float receiver only. A float arriving as a
Variant (loop variable, list element, unannotated parameter) still raises
AttributeError. The fix is one more arm in `PyParseVariantMethod`, mirroring
the str arm that is already there; it is delicate AST surgery and deserves its
own change rather than riding along. `bytes` has no such gap — it is a real
class, so the runtime dispatcher finds its methods already.

## Log
- 2026-08-15 — resolved, commit 9e5b9ebd2.
