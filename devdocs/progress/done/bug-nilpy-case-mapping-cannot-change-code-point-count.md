---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`'ß'.upper()` answers 'ß' where CPython answers 'SS', and `'İ'.lower()` answers 'İ' where CPython answers 'i̇'. pystr_upper/pystr_lower map byte by byte, so a case mapping that changes the code-point COUNT cannot be expressed at all. ASCII and Latin-1 are correct."
status: done
owner: agent-AN
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

## Resolution (2026-08-15) — the obstacle was removed hours earlier

**"Why it is not a small fix" was true when written and is no longer true.**
This ticket's whole argument was that `pystr_upper`/`pystr_lower` walk the
string a byte at a time and replace in place, so a longer result "has nowhere to
go" — and that fixing it meant "a rewrite of the routine around a code-point
cursor and a growable result". That rewrite landed earlier the same day for a
different reason ([[bug-nilpy-non-ascii-string-surface-measured]]: the five case
routines now share one `PyStrMapCase` walker over code points, building a fresh
result). So this is now what the ticket said it was not: a table.

Nor did it need the wider unicode decision it was parked behind
([[feature-unicodestring-model]]) — NilPy strings already carry a code-point
view, because they became character-counted on 2026-08-14.

Added:

- `PyCpUpperStr` — the multi-character UPPER mappings: `ß`, `ŉ`, `ǰ`, `և`, the
  four `ẖẗẘẙ`, and the seven Latin ligatures `ﬀﬁﬂﬃﬄﬅﬆ`.
- `PyCpLowerStr` — the one in the other direction, `İ` -> `i` + combining dot.
- `PyTitleFormOf` — the `capitalize()`/`title()` form, **derived** from the
  upper table rather than tabulated beside it so the two cannot drift.

Two things the CPython diff caught that the obvious implementation gets wrong:

- The title form lowercases everything after the first **CASED** character, not
  after the first character. `'ŉ'.title()` is `ʼN`: the leading modifier
  apostrophe is uncased, so the N is the one that stays upper. Lowering by
  position gave `ʼn`.
- `swapcase` asks "does this have an upper mapping?" to decide direction, and
  asking `PyCpUpper` alone answers "no" for `ß` — whose only upper mapping is
  the multi-character one — so it concluded ß was already uppercase and left it
  alone. `'straße'.swapcase()` is `'STRASSE'`.

Armenian (`Ա-Ֆ` / `ա-ֆ`) went in as a 1:1 pair range on the way: the title form
of the `և` ligature has to lower its expansion's second letter, and ordinary
Armenian text wanted it anyway.

Re-swept exhaustively against CPython over U+0020–U+05FF, U+1E00–U+1EFF and
U+FB00–U+FB1F for `upper`/`lower`/`capitalize`/`swapcase`: **zero wrong
answers** — every remaining divergence leaves the character unchanged.

**Gate:** `test/test_nilpy_case_mapping_expands.npy` (+`.expected`, wired into
the Makefile) — `ß` and `İ` in all five routines, the whole expanding set, the
expansions inside WORDS (where the length change actually has to be carried),
and ordinary letters either side, which is the common path this ticket asked to
pin at the same time. Byte-identical to CPython.
`tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-15 — resolved, commit af9e56651.
