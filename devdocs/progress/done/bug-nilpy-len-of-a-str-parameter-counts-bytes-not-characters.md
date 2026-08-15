---
track: N
prio: 65
type: bug
blocked-by: []
summary: "len(s) on an UNANNOTATED str parameter answers in BYTES while s[i] is bounds-checked in CHARACTERS — so `while i < len(s): out += s[i]` over any non-ASCII text raises IndexError, and the in-range indexes hand back single mojibake bytes. `s: str` is correct; a local is correct; only the unannotated parameter is wrong."
status: done
owner: agent-an-night
---

# `len()` of a `str` parameter counts bytes; `s[i]` counts characters

Found porting [[feature-b-tkhtmlview-in-nilpy]] (Track B), against
`stable_linux_amd64/default/pinned` **v339 / f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c**.

This is the **silent-wrong-value** class: `len()` of a string is about as basic a
question as a program asks, and the answer is wrong by a factor that depends on
the data. CPython accepts and runs the code, so per this repo's NilPy rule
(upward compatibility with CPython) it is a bug, not a dialect divergence.

## Repro

```python
def bare(s):
    return len(s)


def annotated(s: str) -> int:
    return len(s)


lit = "• "
print("local     ", len(lit))        # 2   correct
print("param     ", bare("• "))      # 4   WRONG — the UTF-8 byte count
print("annotated ", annotated("• ")) # 2   correct
print("ascii     ", bare("ab"))      # 2   correct — which is why this survived
```

## What is inconsistent, precisely

An unannotated parameter is being handled as a byte string (AnsiString) for
`len` and `[i]`, and as a real `str` for everything else. Measured on `"• "` /
`"café — naïve"`:

| operation on an unannotated `str` param | answer |
| --- | --- |
| `len(s)` | **BYTES — wrong** |
| `s[i]` | **one BYTE — wrong** (prints as mojibake) |
| `s[a:b]` slicing | characters — correct |
| `for c in s` | characters — correct |
| `s.find(...)` | character index — correct |
| `s.startswith` / `endswith` / `x in s` | correct |
| `s.lower()` | correct |

So `len` and `[i]` are the only two that disagree with the rest — and they
disagree with **each other** in the way that matters: `len` is the byte count but
`[i]` is bounds-checked at the character count, so the canonical loop cannot even
run.

```python
def rebuild(s):
    out = ""
    i = 0
    while i < len(s):
        out += s[i]
        i += 1
    return out

rebuild("café — naïve")     # IndexError: string index out of range
```

Annotate the same function `(s: str) -> str` and it returns the input unchanged.

## Two faces, one cause

1. **loud** — the `while i < len(s)` scan over non-ASCII crashes with IndexError.
2. **quiet, and worse** — a program that only asks `len(s)` gets a plausible
   number that is silently too large. Anything sizing a buffer, aligning a
   column, truncating a preview or asserting a length is wrong on exactly the
   inputs (accents, dashes, symbols) a real document contains, and right on the
   ASCII test data.

## Where to look

The unannotated-parameter path is presumably not getting the `str` kind the
annotated one gets, so `len`/index lower to the Pascal AnsiString `Length`/`s[i]`
rather than the codepoint-aware helpers. Note the fix has to reach **both**
sites: making `len` character-based while `[i]` stayed byte-based would turn the
IndexError into silent mojibake, which is the worse of the two faces.
Per `normalise-dont-special-case.md`, grep for the sibling — anything else keyed
on the same parameter kind (`ord`, `max`/`min` over a string, reversal,
`s[i] = ...`-shaped rewrites) is likely on the same arm.

## Impact seen

The tkhtmlview port's `_emit` crashed on its own list bullet (`"• "`) the first
time a `<li>` was rendered, and every character-scanning helper in the file was
on the same footing. The port was rewritten to `find`/slice/iterate — which is
the more Pythonic spelling anyway and is what the correct rows above make safe —
so it is not blocked, but a library doing character work over user text will meet
this immediately.

## Fixed 2026-08-15 — SIX routines, one arm

The ticket's instinct was right and its guess at the site was not: nothing was
wrong with how an unannotated parameter is TYPED. It is a `Variant`, correctly,
and that is a whole second set of runtime routines — the byte/character split
`feature-nilpy-text-string-kind` moved for the statically-known str was never
moved for the variant arm. Every one of these was still counting bytes:

| routine | what it serves | was |
| --- | --- | --- |
| `pylen_v` | `len(x)` on a variant (ir.inc rewrites the call) | `Length` — BYTES |
| `len(const v: Variant)` | the Pascal-visible overload of the same question | `Length(VariantToStr(v))` |
| `pyvar_getitem` | `s[i]` on a variant | `pystr_ofchar(pystr_at(...))` — the LEAD BYTE |
| `pyord_v` | `ord(c)` on a variant | `Ord(t[1])`, plus a TypeError for a str CPython calls length 1 |
| `max` / `min` `(const s: AnsiString)` | `max(s)` | a `Char` walk over bytes |
| `PYITER_STR` / `PYITER_REVSTR` | `iter(s)`, `reversed(s)` | a byte per step |

`pystr_at` (Char result = lead byte) versus `pystr_charat` (AnsiString = the
whole character) is the byte/char meeting point, and the variant arm was on the
wrong one. `pyord_s` already decoded UTF-8 correctly — `pyord_v` simply never
called it.

**The ticket's warning was exactly right and would have bitten**: fixing `len`
alone turned the IndexError into silent mojibake — measured, `rebuild("café —
naïve")` then returned garbage instead of raising. `len` and `[i]` had to move
together, and so did everything that iterates.

The two iterators keep a BYTE cursor and step over a whole UTF-8 character
rather than switching to a character index — a character-index cursor would
rescan the string per step and make iteration quadratic.

### Verified

Four CPython-3.12 differential sweeps, all byte-identical: the ticket's own
repro table; 13 operations on an unannotated parameter (len, [i], ord, [::-1],
max, min, slice, comprehension, find, upper, [-1], sorted, count); 16 more
covering for-loop variables, dict/list elements, `while i < len(s)` rebuild,
center/ljust/rjust, split/join/replace/strip, `in`/startswith/endswith, encode,
chr, dict comprehension; and 9 iterator shapes (iter, reversed, enumerate, zip,
filter, map, sum-over-genexpr). `bytes` still counts BYTES.

New `test/test_nilpy_str_chars_through_a_variant.npy` + `.expected` (generated
by CPython) in `test-nilpy`, asserting all three shapes that put a str into a
variant. Deliberately a NEW file beside `test_nilpy_str_counts_characters`,
which covers the statically-typed arm — the two arms are the point.

`gate.sh quick` + self-host fixedpoint GREEN. No re-pin needed: `pylib.pas` is
the runtime of a compiled `.npy`, not a unit the compiler links
(project_builtin_change_needs_repin_for_gate_fixedpoint, scope note).

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
