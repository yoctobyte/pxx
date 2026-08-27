---
track: N
prio: 65
type: bug
blocked-by: []
summary: "A NilPy `class Text` still binds the RTL's `Text` file record everywhere except the qualified-construction arm that [[bug-nilpy-text-class-name-binds-the-rtl-file-record]] fixed: `self.f = t.up()` and even `self.f = t` on a `Text` instance SEGFAULT. Renaming the class to anything else makes all three shapes work."
---

# A class named `Text` still segfaults outside the one arm that was fixed

Found 2026-08-27 while fixing
[[bug-n-a-field-takes-its-type-from-the-first-token-of-its-right-hand-side]] —
it was the control written to check that ticket's named hazard (a parameter
shadowing a class name). The hazard did not materialise; this did.

**Pre-existing**: identical under `stable_linux_amd64/default/pinned` and at
HEAD with that fix applied.

```python
class Text:
    def __init__(self, s):
        self.s = s

    def up(self):
        return self.s.upper()


class Wrap:
    def __init__(self, text):
        self.text = text.up()


print(Wrap(Text("ab")).text)     # CPython AB     pxx SIGSEGV
```

## Measured boundary — the shadowing is a red herring

| shape | pxx |
| --- | --- |
| `def __init__(self, text): self.text = text.up()` (param shadows the class) | **SIGSEGV** |
| `def __init__(self, t): self.text = t.up()` (no shadowing at all) | **SIGSEGV** |
| `def __init__(self, text): self.text = text` (single-token RHS) | **SIGSEGV** |
| the same three with `class Text` renamed to `class Boxy` | all correct |

The parameter name does not matter and the right-hand side's shape does not
matter. **The class being called `Text` is the whole trigger.**

## Why this is not the closed ticket

[[bug-nilpy-text-class-name-binds-the-rtl-file-record]] is `done/` and its fix is
real — but it is scoped to ONE arm of the field pre-pass, the QUALIFIED
construction `self.t = tk.Text(...)`, where it calls `FindUClassNonRecord`
instead of `FindUClass`. Its own note in `compiler/pyparser.inc` says so:
"NonRecord, both times". Every other place that resolves a class NAME still
takes the first row, which for `Text` is the RTL's file record — so a field
typed as that record gets a heap object stored in it and the first read walks a
file-variable's guts.

The shape of the real fix is therefore the sibling-grep the closed ticket did
not do: `FindUClass` vs `FindUClassNonRecord` at every name-resolution site that
can see a NilPy class, not just the one that was reproduced. Count them before
choosing; if the answer is "all of them", the honest fix is that NilPy class
lookup never returns a record row at all.

`Text` is not an exotic name — it is a Tkinter widget, and the closed ticket
came from Tkinter code.

## Gate

The four rows above matching CPython, with the class named `Text`, plus the
renamed control.
