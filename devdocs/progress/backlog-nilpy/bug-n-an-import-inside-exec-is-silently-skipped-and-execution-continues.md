---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`exec(\"import math\\nr = math.floor(3.7)\", d, d)` — pyeval's tree-walker discards the import statement without a word and keeps going, so the failure surfaces later as `pyeval: name not defined: math`, naming the module rather than the skipped import. When the imported name is never used there is no error at all and the remaining statements bind normally, which is the accepted-and-ignored failure mode the ambient-exec refusal was explicitly built to avoid."
---

# An `import` inside `exec` is silently skipped, and execution continues

- **Track N** (NilPy semantics; the walker is `compiler/builtin/pyeval.pas`, so a fix
  carries Track A file-ownership — see [[feature-lib-pyexec]]).
- **Found by** frankD (Track D) while documenting exec/eval for `docs/**`
  ([[docs-d-document-exec-eval-and-the-builtins-incompatibility]]). Track D files, does
  not fix.
- **Sibling:** [[bug-n-exec-ignores-a-caller-supplied-builtins-mapping]] — same area,
  same upward-compatibility shape, filed separately.

## Measured, pinned v391, no rebuild

```python
d = {}
exec("import os\nk = 1", d, d)
print(sorted(d.keys()))
```

| | CPython 3.12 | pxx v391 |
| --- | --- | --- |
| keys bound | `['__builtins__', 'k', 'os']` | `['k']` |
| diagnostic | — | **none** |

The import vanished; `k = 1` after it ran and bound normally. Nothing was said.

With the module actually used, the error arrives late and names the wrong thing:

```python
d = {}
exec("import math\nr = math.floor(3.7)", d, d)
print(d["r"])
```

CPython prints `3`. pxx exits 1 with `pyeval: name not defined: math` — pointing at
line 2 for a defect on line 1. A reader sees "math is not defined" directly beneath
`import math`.

## Why this is a bug and not the documented restriction

`feature-lib-pyexec`'s Contract lists "NO import" as a deliberate subset restriction,
and that restriction is fine. **How it is enforced is the defect.** The walker's other
two restrictions announce themselves — a `class` body gives `pyeval: name not defined:
class`, an inner `exec` gives `pyeval: unknown call: exec()` — while `import` alone is
dropped in silence and execution proceeds.

That is precisely the failure mode this area was rebuilt to eliminate. From
`devdocs/dev/nilpy-semantics-divergences.md` on the ambient-`exec` refusal: *"Loud, at
compile time, with the working spelling in the message. That is the opposite of the
failure this whole area just came out of, and it is why it is refused rather than
accepted-and-ignored."* An unannounced skip is accepted-and-ignored.

It also diverges in **control flow**, not only in bindings: CPython raises on a failed
import and abandons the rest of the exec'd source, whereas here the statements after
the import run against a namespace the source never intended to produce. A program
whose import is only for side effects, or whose imported name is never read, gets no
error and a wrong result.

## What would fix it

A diagnostic at the `import` itself, in the shape the ambient refusal already uses —
name the construct, say it is not supported inside `exec`, and give the working
spelling (import in the enclosing module and pass the name in through the namespace
dict). Whether it raises or refuses is the implementer's call; being silent is not.

Note the sibling's diagnostics are themselves poor — `name not defined: class` reports
a keyword as an undefined name — so a fix here may want to widen to "the walker names
unsupported *statements* as unsupported statements". Out of scope for this ticket, but
worth one look while the file is open.

## Verify

Both snippets above, against `$(PXX_STABLE)`, diffed against `python3`. A fix must
keep the ordinary case green: `d = {}; exec("x = 1", d, d)` still binds `x`.
