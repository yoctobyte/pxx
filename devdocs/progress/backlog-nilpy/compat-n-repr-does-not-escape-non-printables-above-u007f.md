---
track: N
prio: 15
type: compat
blocked-by: []
summary: "`repr()` escapes only below U+0080, so C1 controls, NBSP and non-printable astral characters print raw where CPython escapes them: repr(chr(0x80)) is the raw byte here and '\\x80' in CPython. Everything below 0x80 is already correct. Output FORMATTING of a non-float value, so compat at low prio by CLAUDE.md's table."
status: backlog
owner: unassigned
---

# `repr()` does not escape non-printables above U+007F

- **Type:** compat — **Track N** (Nil-Python frontend / RTL repr).
- **Filed:** 2026-08-30 by frankB, noticed while diffing the `codecs` UTF-8
  decoder: the decoded VALUES matched CPython on all 81 cases and only their
  `repr()` rendering differed, which is how the two got separated.
- Measured at pin v395 (`aa78a7faf63a`).

## Measured

| `chr(cp)` | pxx v395 | CPython 3.12 |
| --- | --- | --- |
| `0x07`, `0x1b`, `0x1f`, `0x7f` | `'\x07'` … `'\x7f'` | same ✓ |
| `0x80` (C1 control) | raw byte | `'\x80'` |
| `0x9f` (C1 control) | raw byte | `'\x9f'` |
| `0xa0` (NBSP) | renders as a space | `'\xa0'` |
| `0xe9` (é, printable) | `'é'` | `'é'` ✓ |
| `0xd7ff` (unassigned) | raw | `'퟿'` |
| `0xe000` (private use) | raw | `''` |
| `0x10ffff` (noncharacter) | raw | `'\U0010ffff'` |

So the escaping cutoff is **U+0080** where CPython's is **Unicode
printability** — it escapes categories Cc, Cf, Cs, Co, Cn and the non-space
separators, at any code point.

`test/test_nilpy_repr_escapes_non_printables` passes and is not wrong; its
cases are all below 0x80, which is the half that already works.

## Why prio 15

CLAUDE.md's compat table: *"our output formatting of a value differs → F if it's
a float, else compat at low prio."* This is formatting of a non-float. No
program computes a different answer; `repr` is for humans, and the characters
affected are ones that render as nothing useful either way.

Raise it if something starts comparing `repr()` output as data, or if a
`mimic_` differential needs to assert on strings in this range — the `codecs`
one worked around it by comparing **code points** rather than `repr`, which is
the better assertion anyway and is what a future differential should do.

## What a fix costs, so nobody starts it expecting a one-liner

Doing this *properly* needs Unicode general categories — i.e. a `unicodedata`
table — which is a real dependency and almost certainly not worth it at this
prio.

The **cheap 80%** is the C1 range `0x80..0x9F`, which is unambiguously
non-printable, is what real text actually hits (mis-decoded latin-1, stray
control bytes), and needs no table at all. `0xa0` (NBSP) is a defensible
addition. Astral/unassigned escaping is the part that genuinely needs the
tables; leaving it out is a smaller divergence than the C1 gap and can stay.

Whoever takes it: say in the commit which of those two tiers landed, so the
ticket does not read as fully closed when only the cheap half is done.
