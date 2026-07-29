---
track: N
prio: 70
type: bug
---

# `from m import f` makes every def in an imported module use the function-object ABI

The name in a `from <module> import <name>` statement is a BARE identifier, so
`PyDefUsedAsValue` (pyparser.inc) counts it as "used as a value" and normalises
that def to the function-object ABI: variant result, and **every parameter
forced to `tyVariant`** (pyparser.inc, `PyParseDefHeader`, the
`if PyDefUsedAsValue(PyHdrName)` block).

For most parameter types the boxing is only wasteful. For a
`Callable[...]` parameter it is fatal: the callee's `cb` slot becomes a variant
(passed by reference), while the call site still hands over a function VALUE,
and the callee's `call_ind` then jumps to the variant's TAG word.

## Repro — SIGSEGV, CPython prints `['C', 'C']`

```python
# kalib2.py
from typing import Callable
def run2(chords: list[str], cb: Callable[[str], list[str]]) -> list[str]:
    return cb(chords[0])
```
```python
# drv2.py
from kalib2 import run2

def notes_of(ch: str) -> list[str]:
    return [ch, ch]

print(run2(["C"], notes_of))     # SIGSEGV
```

This is the standing wall in songformatter's key analysis (`~/songformatter`,
`kadrv.py`), where gdb names it
`NoteCountingDetector.analyze (..., chord_to_notes=0x2, ...)` — 0x2 is a variant
tag word, not a value. Not a regression: reproduces against a compiler built
from `b7c524a89`.

## Measured, do not re-derive

- The identical shape **inside one module works**. Cross-module is the trigger.
- `notes_of`'s own IR is byte-for-byte the same in both cases — the callee, not
  the passed def, is what differs.
- `PXXDBG=a.ir:run2` cross-module: `lea [sym=chords]` + helper 407 (variant
  subscript). Single-module: `load_sym [sym=chords] tk=6` + helper 162 (TPyList
  subscript). Every annotated parameter of a module def is a variant.
- Decisive check: rewriting the driver as `import m3` + `m3.first(...)` — so the
  name never appears bare — restores `load_sym ... tk=6`. The import statement
  IS the false positive.

## Fix direction

`PyDefUsedAsValue` must not count a mention that is part of an import
statement (a logical line opening with `tkUses` (`import`) or the ident `from`).
Narrowing its scan to `PyScanLo..MainProgramTokCount` instead would ALSO cut the
false positive, but it would lose the genuine case — a def in a module passed as
a value by the main program — so the import-line skip is the right cut.

## RESOLVED @ 242b96878

`PyDefUsedAsValue` now skips a logical line that opens with `import` (tkUses)
or the ident `from`. The scan is deliberately NOT narrowed to the current unit:
a def defined in a module and passed as a value by the main program is the
genuine case, and it lives outside PyScanLo.

The repro stopped crashing but still returned `[]` — a SECOND, independent
defect in the same wall: module code got no return-ownership retain, so the
caller received a reference the callee's scope exit had already dropped. Fixed
in 33db0107d ([[bug-nilpy-object-reclamation-disabled-inside-py-modules]]).
With both, seven cross-module callable shapes match CPython exactly.

Gate: tools/gate.sh quick GREEN at the time of the fix; the follow-up landed
under tools/gate.sh full GREEN.

## Log
- 2026-07-29 — resolved, commit 242b96878.
