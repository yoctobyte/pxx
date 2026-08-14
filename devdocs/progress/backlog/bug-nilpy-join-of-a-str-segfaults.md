---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`\"-\".join(\"hello\")` SEGFAULTS — pystr_join is reached by name and takes a TPyList, so a string handle is dereferenced as an object pointer; str is an iterable in CPython and join accepts it"
status: backlog
---

# `sep.join(str)` dereferences a string handle as an object

- **Type:** bug (crash, no diagnostic) — **Track N**

## Repro

```python
print("-".join("hello"))
```

CPython: `h-e-l-l-o`.
pxx at pin **v291** and every pin before it: **Segmentation fault**, no
diagnostic, rc 139.

Not specific to non-ASCII — plain `"hello"` crashes.

## Cause

`pystr_join(const sep: AnsiString; l: TPyList)` is reached **by name**
(`FindProc('pystr_join')` in `PyStrMethodFinish`), not by overload resolution,
so nothing type-checks the argument. An `AnsiString` argument passes the string
HANDLE where a `TPyList` object pointer is expected and it is dereferenced.

This is exactly the shape of
`bug-nilpy-str-iterable-builtins-segfault-on-a-string-handle`, which was fixed
for `zip` / `enumerate` by wrapping a str argument in `PyIterArgAsList` (→
`pystr_charlist`). `join` has the same defect and was not covered by that fix —
a sibling that stayed broken, the pattern
`devdocs/dev/normalise-dont-special-case.md` warns about.

## Current state (2026-08-14, sha PENDING)

`feature-nilpy-text-string-kind` changed the symptom, not the bug: the argument
now arrives as something `pystr_join`'s item loop rejects, so it raises
`TypeError: sequence item 0: expected str instance` instead of crashing. Loud
beats silent, but it is still wrong — CPython joins it.

## Fix

Route a str argument to `pystr_join` through `PyIterArgAsList` (or call
`pystr_charlist` directly at the join site), the same way `zip`/`enumerate`
already do. Then **grep for the other by-name `FindProc` calls that take a
`TPyList`** — the whole point of this ticket is that the zip/enumerate fix left
siblings behind, and closing only `join` would repeat that.

CPython's `join` takes ANY iterable, so a generator/cursor argument is the next
shape after str; `PyDrainIfCursor` is already applied at that site for exactly
that reason, which shows the site is the right place for the str case too.

## Gate

`make compiler/pascal26` + the repro + `tools/gate.sh quick`. Add the repro to
the nilpy suite alongside `test_nilpy_str_counts_characters.npy`.
