---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`def open(x)` in a .npy is silently ignored — the builtin runs and raises FileNotFoundError instead of calling the user's function. Python lets a def shadow any builtin, and 13 of the 17 builtins swept get this right; open's intercept never asks. Silent wrong behaviour, not a refusal."
status: done
---

# A user `def open()` is silently ignored

```python
def open(x):
    return "USER:" + x

print("got", open("f"))
```

CPython prints `got USER:f`. pxx raises `FileNotFoundError: f` — the builtin
intercept claimed the call and the user's function was never reached. No
diagnostic.

Found 2026-08-13 sweeping every intercepted builtin for the shadowing question
while examining [[decide-nilpy-builtin-vs-pascal-unit-name-resolution]].

## The sweep that found it

`def <name>(x): return "USER"` then `<name>(3)`, 17 builtins:

| result | names |
| --- | --- |
| user def wins — CPython's answer | len, sum, sorted, max, min, format, input, str, abs, round, enumerate, callable, repr |
| refused with a diagnostic | print (it LEXES to a token), zip, type |
| **silently ignored** | **open** |

So the majority is right and this one is not. The three refusals are their own
(smaller) problem — a diagnostic is honest, a wrong answer is not.

## Cause

Each intercept decides the shadowing question independently, with a different
mechanism: a lexer keyword (`print`), `PyUserShadowsProc` (`enumerate`),
`FindSym(name) < 0` (`input`, `type`), `ProcUnitIdx = -1` (`format`). The `open`
arm — `else if isNilPy and (name = 'open')` in parser.inc — has NO guard at all.

That is the "one concept, N independent sites" shape this repo keeps paying for
(devdocs/dev/normalise-dont-special-case.md): fix `open` and the next intercept
added will forget again.

## Shape of a fix

The one-line version is to give the `open` arm the same guard its neighbours
have. The right version is one predicate every intercept calls — "does the
program's own code bind this name?" — which is what
[[decide-nilpy-builtin-vs-pascal-unit-name-resolution]] is deciding the shape
of. Do the one-liner if that ticket is still open; do not add a fifth
mechanism.

## Gate

The sweep above as a `.npy` diffed against CPython: a `def` of each intercepted
builtin, called, plus the builtin still working in a program that does NOT
define it. `zip`/`type`/`print` may stay refusals in this ticket — they are
diagnostics, not wrong answers — but say so in the test.

## Log
- 2026-08-14 — resolved, commit 5aac2701c.

## Resolution (2026-08-13)

Fixed as the ticket's "right version", not its one-liner, because the governing
rule ([[feedback_reference_compat_is_the_default_shadowing_allowed]]) says the
default follows CPython and a design question is not settled by what is
cheapest.

`PyUserShadowsProc` (symtab.inc) already IS the predicate — about ten
name-keyed lowerings ask it, and it knows the part any ad-hoc guard would miss:
Python rebinds the name only from the `def` statement ONWARD, so a call above
the def still reaches the builtin. Four arms answered the question themselves
instead — `open` not at all, `zip`/`type` via their own conditions, `format`
via a bespoke `ProcUnitIdx = -1` check added the same day — and they now ask it.
That is four mechanisms down to one, which is the gate clause this ticket's
parent decision asks for.

Sweep of all 17 intercepted builtins against CPython: **16 agree, up from 13.**

| result | names |
| --- | --- |
| user def wins | len, sum, sorted, max, min, format, input, str, abs, round, enumerate, callable, repr, **zip, type, open** |
| refused | print |

`print` stays refused because it LEXES to `tkwriteln` — an implementation
accident, not a decision, and it is the open question in
[[decide-nilpy-builtin-vs-pascal-unit-name-resolution]] rather than something
quietly kept. Every builtin still answers correctly when NOT shadowed (checked:
all 17 in one program, plus the file round-trip through `open`).

Test `test/test_nilpy_user_def_shadows_a_builtin.{npy,expected}`, wired into
`test-nilpy`; the zip/enumerate/format/f-string families re-run by name.
