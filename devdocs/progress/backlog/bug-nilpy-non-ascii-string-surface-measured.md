---
track: N
prio: 35
type: bug
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

## Gate

`make test-nilpy` + self-host byte-identical, plus the table above.
