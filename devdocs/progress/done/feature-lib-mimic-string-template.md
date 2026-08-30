---
track: B
prio: 12
type: feature
blocked-by: []
summary: "string.Template — the $-placeholder class (substitute, safe_substitute) — is the one member of Python's string module still missing, and it is what logging/__init__.py uses. Deliberately NOT urgent: `import logging` does not resolve at all today, so nothing can reach Template until a logging shim exists. Split out of feature-lib-mimic-string, which shipped every constant and both capwords forms."
status: done
owner: frankB
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

## 2026-08-30 (frankB) — IMPLEMENTED. The blocking question was answered YES.

### The open question, answered by running it

The previous note ended: *"whether Pascal can index a Python dict held in a
`Variant` … Answer that dict question first; if a Variant dict cannot be read
from Pascal, this ticket needs an IR/frontend change and is no longer Track B
alone."*

**It can, and the recipe already existed in the tree** —
`mimic_urllib_request.pas:560` does exactly this for a headers dict. The probe
that answers it (named `mimic_dprobe`, since a `.pas` unit is reachable from
`.npy` only through shim resolution — the trap the last session hit):

```pascal
if pyvar_is_objtag(m) then
  if TObject(pyvarobj(m)) is TPyDict then
    d := TPyDict(pyvarobj(m));
```

`d.count`, `d.indexof(k) >= 0`, `d.fetch(k)`, `d.keylist` all work, and the probe
matched CPython exactly on values, presence, count **and key order**. Note the
presence test is `indexof(k) >= 0`; there is no `haskey`. So this stayed Track B
alone and needed no IR change.

### The keyword-argument limit is real, and confirmed by measurement

`t.substitute(who='tim')` is rejected at compile time:

```
error: Nil Python: Template.substitute has no parameter named 'who'
```

which is the loud failure `python-compat-tiers.md` requires. The shim's header
states the subset and quotes that exact diagnostic — verified verbatim, not
paraphrased from memory.

### A SECOND limit was found, and it is not this class's fault

The previous note assumed `substitute(**values)` — what
`logging.StringTemplateStyle` actually calls — would work through the mapping
path. **It does not, for an unrelated reason:** `**` unpacking is a parse error
at *any* method call in this dialect, pure-Python classes included.

| call shape | v395 |
| --- | --- |
| `f(**d)` plain function | ok |
| `c.m(**d)` method, pure Python | `error: expected expression` |
| `c.m(*[1,2])` method without defaults | ok |
| `c.m(*[1,2])` method with defaults | explicit refusal naming defaults as the reason |

Filed as [[bug-n-double-star-unpacking-is-rejected-at-a-method-call]] (Track N,
p45) with the single-star measurement included, because an early draft of that
ticket guessed `*` and `**` were one gap and the measurement showed they are two
with different shapes — `*` is implemented with a stated limit, `**` is not
parsed at all. **This class needs no change when that closes**, which is why
`mapping` is a `Variant` rather than something narrower.

### Implementation

`lib/rtl/mimic_string.pas` — `Template` with `template`, `Create`,
`substitute`, `safe_substitute`, and **one shared `Render(mapping, safe)`**
behind both. Written once deliberately: the two methods differ *solely* in what
they do on a missing key and a malformed placeholder, and two scanners would be
two places for the `$$`/brace/greedy-identifier rules to drift apart — the
double-case shape `normalise-dont-special-case.md` warns about.

### Gate: 43-check CPython differential, byte-identical

`test/lib_mimic_string_template.npy` runs unmodified under CPython 3.12 and
**both outputs are byte-identical**, 43/43, `MIMIC-STRING-TEMPLATE OK`. Wired
into `lib-test` after the `lib_mimic_weakref` entry.

Derived by diffing CPython, per this ticket's own instruction — and it earned
its keep. **Two behaviours are not in the prose docs and would have shipped
wrong from the plausible reading:**

1. `safe_substitute` **keeps the braces** on an unresolved braced placeholder.
   The result is the full braced form, *not* the bare dollar-name form. The two
   spellings are not normalised to each other on the way out.
2. An **unterminated** braced placeholder is a `ValueError` from `substitute`
   **even when its name is present in the mapping** — the placeholder is
   malformed and CPython never reaches the lookup.

Also pinned: `$$` consumed whole (so `$$who` is text, never a lookup — the test
passes a mapping that *would* resolve it if the rule were wrong), greedy
identifiers (`$x_y` beats `$x`), identifiers stopping at `-`/`.`, and `str()`
coercion of non-string values including `None`.

### Cost note, recorded because it is repeatable

Four compiles were lost to one dialect property: **`{ }` comments NEST here, and
quotes do not protect a brace inside one.** Writing `${who}` in a doc comment
opens a nested comment at `{` and closes the outer one at `}`. The diagnostic is
poor in the way that matters — the open-brace case reported `unterminated
comment` at the comment's *start*, 48 lines above the offending character, and
one intermediate state reported `unexpected character` on a line reading only
`begin`. Not filed: no program behaves wrong, and CLAUDE.md ranks diagnostic
quality low by explicit ruling. Recorded here because the next person writing a
`mimic_` shim about a brace-using syntax will hit it, and the fix is to spell
braces in words inside comments.

### Sequencing unchanged

`import logging` still does not resolve, so nothing in the stdlib reaches
`Template` yet. This closes on its own differential — the gate this ticket
named — not on a stdlib consumer.

### Gate run

`make lib-test` against pin v395: **ok, exit 0**, with
`lib_mimic_string_template.1` (43) and `.2` (`MIMIC-STRING-TEMPLATE OK`) both
passing inside the real run, not just standalone. 142 units still compile. The
two pre-existing consumers of this unit — `test_nilpy_import_string_module` and
`test_nilpy_repr_escapes_non_printables` — were checked against CPython
separately and still match, since adding `uses pylib, sysutils` to the
implementation changes what every `import string` program pulls in.

## Log
- 2026-08-30 — resolved, commit a627e019c.
