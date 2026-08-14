---
track: N
prio: 35
type: bug
status: done
owner: agent-AN
---

# The measured non-ASCII surface: `len`, `upper`, `chr`, `ord` all diverge

NilPy strings are byte strings, knowingly — see
[[bug-nilpy-encode-ignores-the-codec]], landed that way for the uforth drive.
This ticket records what that costs at the surface, measured rather than
assumed, so the next person picking up the string model has the list:

| expression | CPython | pxx |
| --- | --- | --- |
| `len("héllo")` | 5 | **6** (UTF-8 bytes, not code points) |
| `"héllo".upper()` | `HÉLLO` | **`HéLLO`** (non-ASCII left alone) |
| `chr(233)` | `é` | **a lone `0xE9` byte** — invalid UTF-8 on stdout |
| `ord("é")` | 233 | **`TypeError: ord() expected a character, but string of length 2 found`** |

Everything ASCII matched exactly in the same sweep: indexing, negative
indexing, concatenation, repetition, `\t` / `\n` / `\\` escapes, single vs
double quotes, nested quotes, `in`, `split`, `split(sep)`, `join`, `replace`
with a count, `capitalize`, `%`-formatting of None, and `f"{s!r}"`.

`len` is the one that silently corrupts logic — a length used as an index or a
loop bound is wrong for any non-ASCII text, with no error. `chr` is the one
that corrupts OUTPUT: it writes a byte that is not valid UTF-8, so the terminal
shows a replacement character and a downstream reader may reject the stream.

## Not a re-litigation of the model

The byte-string choice is deliberate and cheap and should not be reversed on
the strength of this table. Two things are worth doing WITHIN it:

- `ord`/`chr` should agree with each other and with the model — either both
  byte-oriented (so `chr(233)` is documented as a byte and `ord` takes one
  byte) or both code-point-oriented. Today `ord` rejects what `chr` produces,
  which is incoherent under either reading.
- `upper`/`lower` over latin-1 bytes is a 256-entry table, not a Unicode
  database, so the common European case is affordable.

Whether `len` should count code points is the real fork, and it belongs with
the string model rather than here.

## Partially addressed (this session) — `chr`/`ord` coherence, `upper` still open

Measured (not assumed): `chr` and `ord` were already self-consistent under
the byte model (`ord(chr(233))` round-trips to `233` today, before any
change here) — the incoherence in the original framing was really about a
2-byte UTF-8 SOURCE LITERAL (`"é"`, 2 bytes) vs `chr`'s 1-byte OUTPUT, which
is the byte-vs-codepoint model question this ticket correctly defers, not a
`chr`/`ord` disagreement to fix in isolation.

What WAS a real, narrowly-scoped bug, found while checking the above:
`chr()` outside 0..255 (`chr(8364)`, the € sign) silently TRUNCATED via the
raw `Chr` intrinsic's mod-256 cast — `chr(8364)` gave the wrong byte `172`,
no error — worse than this ticket's own repro (`chr(233)`, which is at least
in-range). Fixed: `chr()` in NilPy now raises `ValueError` outside 0..255
(new `PyChrRangeCheck` in pylib.pas, wired into the `Chr` intrinsic dispatch
in parser.inc, gated on `PyExprMode` so the Pascal frontend's own `Chr` is
untouched). This doesn't resolve the byte-vs-codepoint fork — it just stops
the byte model from silently lying about a value it cannot represent.
Regression: `test/test_nilpy_chr_range_check.npy`.

Still open, deliberately not attempted here (all belong with the real fork
noted above): `len()` counting bytes not code points, `upper`/`lower` only
handling ASCII (the ticket's own suggested cheap win — a latin-1 256-entry
table — not done this pass), and `chr(233)`/`ord("é")`'s underlying
byte-vs-codepoint mismatch with actual UTF-8 source text.

## Gate

`make test-nilpy` + self-host byte-identical, plus the table above.


## 2026-08-08 — a claim made here and RETRACTED

I appended a section asserting that this model breaks uforth's `.(` word and 2
of the 11 files in its driver suite. **That was wrong and has been removed.**

`.( abc)` — pure ASCII, no non-ASCII anywhere in the input line — failed
identically, which the byte-string model cannot explain and which I had already
measured before writing the claim. The real cause was
[[bug-nilpy-return-none-from-a-str-returning-def-yields-the-text-None]]: `.(`'s
loop exits on `if tok is None: break`, and `next_token()`'s None came back as
the TEXT 'None'. Fixed; the suite is now 10/11.

What IS true and worth keeping is only the raw measurement, which reproduces:

```python
print(len("———"))      # CPython 3   pxx 9
t = "abc—def"
print(len(t), t[4:])   # CPython 7 def      pxx 9 <invalid UTF-8 on stdout>
```

i.e. the `len` row of the table above also reaches SLICING, and a mid-character
slice puts invalid UTF-8 on stdout — the `chr` row's corruption arrived at
through a different door. That is a genuine addition to this ticket's list. It
cost nothing here: uforth's non-ASCII is confined to comments.

## Resolution (2026-08-15) — the table is now green, minus the count-changing fork

**Re-measured at HEAD first, and most of the original table was already fixed**
by the 2026-08-14 change that made a NilPy str character-counted and `s[i]` a
one-character str. `len("héllo")` is 5, slicing is character-aligned,
`ord("é")` is 233 and `chr(233)` prints `é` — all four rows of the ticket's
table that were about counting are gone, and the "real fork" the ticket defers
was in fact decided and built. A ticket's measurements age; this one had.

Two things were genuinely still wrong, and both are fixed here.

**1. `upper`/`lower`/`capitalize`/`title`/`swapcase` only touched ASCII.**
Now one walker (`PyStrMapCase`) decodes UTF-8, maps the code point and
re-encodes — five entry points through ONE routine, because five copies of
"decode, map, re-encode" is how the next gap gets fixed in four places and
missed in the fifth. The mapping (`PyCpUpper`/`PyCpLower`) covers ASCII,
Latin-1 Supplement, Latin Extended-A, Greek (including the accented vowels,
whose capitals sit in a separate block) and Cyrillic — the ticket's suggested
"256-entry table", done at code-point level because the strings are UTF-8.

Verified by an **exhaustive sweep of every printable code point from U+0020 to
U+0500 against CPython**, which is what caught the two real traps:

- Latin Extended-A is not uniformly even-upper. The band flips at $139–$148
  (that is where Ł/ł live) and again at $179–$17E, so a single even/odd rule
  left `'łódź'.upper()` with one letter unchanged.
- The Turkish dotted/dotless I looks like an adjacent pair and is not:
  `'ı'.upper()` is ASCII `I` and `'İ'.lower()` is two code points. Read as a
  pair it produced İ and ı — **the only two characters in the whole sweep where
  we answered a DIFFERENT character rather than none.**

The sweep's closing state: **zero wrong answers.** Every remaining divergence
from CPython is a character left unchanged (Latin Extended-B, IPA, the Greek
and Cyrillic extension blocks), which is the honest failure here, and the
count-changing cases (`'ß'.upper()` is `'SS'`, `'ﬁ'.upper()` is `'FI'`,
`'ŉ'`, `'İ'.lower()`) which belong to
[[bug-nilpy-case-mapping-cannot-change-code-point-count]].

**2. `sorted(s)` and `tuple(s)` exploded a string by BYTES.** `sorted("béa")`
answered four elements where `list("béa")` answered three, splitting the é into
its two UTF-8 bytes. Both now go through `pystr_charlist` — the note already on
that routine says "one exploder, not two", and this was the third and fourth
copy. `list`/`tuple`/`sorted`/`zip`/`enumerate`/`for` now agree about how many
characters a string has.

**Gate:** `test/test_nilpy_non_ascii_case_and_explode.npy` (+`.expected`, wired
into the Makefile) — the five case routines over Latin-1, Polish, accented
Greek and Cyrillic, an uncased character in both directions, list/tuple/sorted
agreeing on element counts, and ASCII controls. Byte-identical to CPython.
`tools/gate.sh quick` GREEN, self-host byte-identical.

**Still open, unchanged:** the count-changing mappings (own ticket, linked
above). The byte-vs-code-point model question this ticket deferred is settled —
NilPy strings are UTF-8 and character-indexed.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
