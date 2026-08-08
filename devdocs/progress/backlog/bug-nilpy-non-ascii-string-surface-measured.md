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

## 2026-08-08 — a measured COST of the model: it breaks uforth's own test suite

The ticket asks for the cost to be recorded rather than assumed. Here is a
concrete one, found while clearing uforth's blocker chain.

`.( hello)` — the ANS Forth "print until `)`" word — prints **nothing at all**
under pxx, with no diagnostic. It is why `tests/_drv_string.fth` and
`tests/_drv_x.fth` are 2 of the 3 files in uforth's driver suite that still
differ from CPython (the other 8 are byte-identical).

The mechanism is `len`-as-bytes reaching an INDEX, exactly the silent-corruption
case the table above calls out:

```python
def w_dot_paren(vm):
    pos = int.from_bytes(vm.memory[SYS_IN_ADDR:SYS_IN_ADDR+8], 'little', signed=True)
    line = vm.input_line[pos:]        # pos is a BYTE offset into the TIB
    ...                               # input_line is indexed by CHARACTER
```

uforth writes `>IN` as a byte offset into its memory-mapped TIB and then uses it
to slice a Python str. Under CPython the two disagree only for non-ASCII text;
under pxx they agree — but `.UFO` sources are full of em-dashes, so the same
line measures 53 under CPython and 67 under pxx, `pos` lands past the end, and
the slice is empty. Visible directly in uforth's own trace:

```
cpython: [trace:source] ... len=53 text="\ ——— .( — print tokens ... ———"
pxx    : [trace:source] ... len=67 text="\ ——— .( — print tokens ... ———"
```

Reduced to five lines:

```python
print(len("———"))      # CPython 3   pxx 9
print("\\ ———"[0:5])    # CPython "\ ———"   pxx "\ —"
t = "abc—def"
print(len(t), t[4:])   # CPython 7 def      pxx 9 <invalid UTF-8>
```

Note the last one also puts a MID-CHARACTER byte sequence on stdout, i.e. the
`chr` output-corruption row of the table reached through slicing rather than
through `chr`.

### What this does and does not argue

It is not an argument to reverse the model — the ticket's own framing stands.
It is an argument that the cost is no longer hypothetical: a real program in the
corpus that motivated the byte-string choice is itself broken by it, silently,
and the failure surfaces four layers from the cause (empty output from one Forth
word). Whoever picks up the string model should weigh that; whoever does not
should expect `.(`-shaped mysteries in any corpus with non-ASCII source.

Cross-referenced from [[bug-nilpy-uforth-dot-paren-prints-nothing]].
