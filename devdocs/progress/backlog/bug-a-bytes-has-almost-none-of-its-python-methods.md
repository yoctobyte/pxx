---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`bytes` carries decode/find/endswith/hex/count and essentially nothing else — no lower, upper, startswith, split, strip, replace, join, translate, index. `b.lower()` is what stops webencodings, and every one of these is reachable from ordinary CPython code that has no reason to expect a gap."
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
