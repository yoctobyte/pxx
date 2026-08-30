---
track: B
prio: 12
type: feature
blocked-by: []
summary: "string.Template — the $-placeholder class (substitute, safe_substitute) — is the one member of Python's string module still missing, and it is what logging/__init__.py uses. Deliberately NOT urgent: `import logging` does not resolve at all today, so nothing can reach Template until a logging shim exists. Split out of feature-lib-mimic-string, which shipped every constant and both capwords forms."
---

# `string.Template` — the `$`-placeholder class

- **Type:** feature (library) — **Track B** (`lib/rtl/mimic_string.pas`).
- Split out of [[feature-lib-mimic-string]] on 2026-08-15, which closed with
  every constant and both `capwords` forms matching CPython 3.12. `Template` is
  the remainder.

## Why it is prio 15 and not higher

It is the member the stdlib actually uses — `logging/__init__.py` is the only
one of the ten `string`-importing stdlib modules that reaches past the
constants, and it reaches for `Template`. But **`import logging` does not
resolve at all today**:

```
error: import: no unit named logging and no shim mimic_logging
```

So nothing can reach `Template` until a `logging` shim exists, and writing it
first is building the second storey. Sequence it behind that; raise the prio the
moment `logging` lands.

Directly-written `string.Template` in application code is rare — it is the
`$name` templating class most people skip in favour of f-strings or `.format()`.

## Surface

```python
t = string.Template('$who likes $what')
t.substitute(who='tim', what='kung pao')      # raises KeyError if missing
t.safe_substitute(who='tim')                  # leaves '$what' in place
```

- `$$` is a literal `$`.
- `$name` and `${name}` are both placeholders; `${name}` is what makes
  `${noun}ification` work.
- An identifier is `[_a-z][_a-z0-9]*`, case-insensitive.
- `substitute` raises `KeyError` for a missing key and `ValueError` for a
  malformed placeholder; `safe_substitute` raises **neither** and leaves the
  original text.
- Class attributes `delimiter` and `idpattern` are overridable in CPython —
  almost certainly out of scope for a first cut, but say so explicitly rather
  than leaving it ambiguous.

## Note for whoever takes it

Derive the behaviour from a CPython diff, not from the docs — the
`feature-lib-mimic-string` close is a worked example of why: `capwords(s, sep)`
looked like a variation of `capwords(s)` and is a different function, and three
of five edge cases would have shipped wrong from the plausible reading.

## Gate

A `.npy` diffed against CPython 3.12: `substitute` and `safe_substitute`, `$$`,
`$name`, `${name}`, `${name}` adjacent to text, a missing key on both methods, a
malformed placeholder on both, and a non-identifier after `$`. Build with
`$(PXX_STABLE)`; do not rebuild the compiler.

## Investigation note 2026-08-30 (frankB) — the kwargs problem, before anyone starts coding

Looked at, not claimed; reprioritised away before implementation. What was
established is recorded here so the next person does not re-derive it.

**`string` is a Pascal unit (`lib/rtl/mimic_string.pas`), and that decides the
shape of `Template`.** Thirteen of the seventeen shims in `lib/rtl` are `.py`
and four are `.pas`; a module resolves to exactly one shim, so `Template` cannot
be added as Python beside a Pascal `string`. It has to be a Pascal class.
Precedent exists — `mimic_codecs.pas`, `mimic_urllib_request.pas` and
`mimic_urllib_error.pas` all declare classes that NilPy constructs and calls,
including with keyword arguments (`codecs.IncrementalEncoder(errors='strict')`
→ `constructor Create(const errors: AnsiString = 'strict')`).

**But the keyword form of `substitute` cannot work that way.** CPython's
signature is

```
substitute(self, mapping={}, /, **kws)
```

and NilPy's keyword-call support binds a keyword to a **declared parameter
name** — which is why the tkinter façade works, its names being fixed and
declared. `Template.substitute`'s keyword names are the caller's *placeholders*,
unknown at compile time, so `t.substitute(who='tim')` has no declared parameter
to bind to and will be rejected with *no parameter named 'who'*.

**The mapping form is expressible and is what the stdlib consumer needs.**
`t.substitute({'who': 'tim'})` is valid CPython and equals the keyword form.
`logging.StringTemplateStyle` calls `self._tpl.substitute(**values)` — dict
unpacking, i.e. the mapping path semantically, not a literal keyword list.

So the shape to build is `substitute(mapping: Variant)` /
`safe_substitute(mapping: Variant)`, with the literal-keyword form **failing
loudly** — which is what `devdocs/dev/python-compat-tiers.md` requires anyway: a
shim states its subset in its own header and fails loudly outside it, never
approximating. Say so in the header rather than leaving a caller to discover it.

**Open question that stops this being a pure library job:** whether Pascal can
index a Python dict held in a `Variant` (`m[key]`, `m.__contains__(key)`). No
helper for it exists in `lib/rtl` or `compiler/builtin`. A probe was written and
did not get to answer the question, because it tripped a different thing first:

```
error: import: probe_dict is the Pascal unit .../probe_dict.pas,
       not a Python module
```

A `.pas` unit is not importable from `.npy` by its own name — it is reached only
through the `mimic_` shim resolution (`import string` → `mimic_string.pas`). So
the probe must be named `mimic_<something>` and imported without the prefix.
**Answer that dict question first**; if a Variant dict cannot be read from
Pascal, this ticket needs an IR/frontend change and is no longer Track B alone.

The ticket's own sequencing note still holds: `import logging` does not resolve
at all today, so nothing in the stdlib can reach `Template` regardless.
