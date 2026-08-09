---
track: N
prio: 30
type: feature
---

# `"%(k)s" % {...}` — the mapping form of %-formatting

```python
print("%(k)s" % {"k": "v"})
```

```
Unhandled exception: ValueError: unsupported format character "("
```

Fails at RUN time with a named ValueError quoting the character it could not
handle — visible, not a wrong string.

Positional %-formatting is complete: a sweep against CPython matched `%s %d
%.2f`, `%x/%o`, `%e/%g`, sign flags, thousands separators and `*` width. The
mapping form is the remaining spelling, and it is the one logging and templating
code uses because it survives reordering.

The parenthesised NAME is the whole feature: `%(name)s` looks up `name` in the
right-hand mapping instead of consuming the next positional argument, and the
rest of the conversion (flags, width, precision, type) is unchanged — so the
existing spec handling is reused and only the argument SOURCE differs.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over a mapping with
several keys, a key used twice, a missing key (KeyError, now that a KeyError
names its key), mapping keys combined with flags/width/precision, and a literal
`%%` alongside.

## 2026-08-09 — IMPLEMENTED

The key is parsed BEFORE the flags (`%(name)-10s`) and the rest of the
conversion is unchanged, so the existing spec grammar is reused exactly as the
ticket expected — only the argument SOURCE differs.

The subtlety worth keeping: a mapping placeholder consumes **no positional
argument**, so the positional counter must not advance. `"%(k)s %(k)s"` is what
pins it — one key read twice, which a counter-advancing implementation gets
wrong on the second placeholder only.

A missing key raises KeyError NAMING the key, which works because the dict fetch
already raises a proper KeyError as of the same day's
`bug-nilpy-exception-str-and-repr-diverge-from-cpython` fix — so that case also
guards this fix from the other direction.

Verified against CPython: repeated keys, out-of-order keys, every
flag/width/precision combination through a mapping key, a literal `%%` beside
one, the missing-key KeyError, and the positional forms as controls.
`gate.sh quick` GREEN.
