---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`'ß'.upper()` answers 'ß' where CPython answers 'SS', and `'İ'.lower()` answers 'İ' where CPython answers 'i̇'. pystr_upper/pystr_lower map byte by byte, so a case mapping that changes the code-point COUNT cannot be expressed at all. ASCII and Latin-1 are correct."
---

# NilPy case mapping cannot change the code-point count

Split out of
[[bug-nilpy-small-builtin-surface-gaps-found-by-the-2026-08-13-sweep]] when its
other three rows shipped. That ticket had already scoped this one to "the wider
unicode question rather than to itself"; this file is so the row is not lost
inside a resolved ticket.

| shape | pxx | CPython |
| --- | --- | --- |
| `"ß".upper()` | `ß` | `SS` |
| `"İ".lower()` | `İ` | `i̇` |

## Why it is not a small fix

`pystr_upper` / `pystr_lower` walk the string a byte at a time and replace each
byte in place. A mapping whose result is LONGER than its input has nowhere to go
in that loop — the shape cannot express the answer, so this is a rewrite of the
routine around a code-point cursor and a growable result, not a table entry.

That in turn wants the wider unicode decision: whether NilPy strings carry a
code-point view at all, and where the case tables live. See
[[feature-unicodestring-model]].

## Scope of the wrongness

A **wrong value**, not a refusal — but only for non-ASCII letters whose case
change alters length. Every ASCII and Latin-1 letter is already correct, which
is why this sat at the bottom of the sweep.

## Gate

A `.npy` diffed against CPython covering `ß`, `İ`, and a few ordinary letters
either side of them, so the common path is pinned at the same time.
