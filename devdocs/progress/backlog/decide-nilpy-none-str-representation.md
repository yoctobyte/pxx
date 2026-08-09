---
track: U
prio: 45
type: decide
summary: "`\"\" is None` is True for a statically str-typed value and False for the same string in a variant — the variant path ALREADY models None-vs-empty correctly, so choose: route str Optionals through variants, give None-str a distinguished non-nil handle, or leave the divergence documented"
---

# How should a NilPy `str` represent None?

Requested by [[bug-nilpy-empty-str-and-none-are-the-same-value]], which says in
so many words that this is a model decision and should not be picked in passing.
Two neighbours circle the same model:
[[bug-nilpy-non-ascii-string-surface-measured]] and
[[bug-nilpy-encode-ignores-the-codec]].

## The measurement that shapes the choice (2026-08-09, HEAD)

The bug ticket reports `"" is None` answering True. Measured across shapes, the
failure is **not uniform**, and that is the useful part:

| operand | `"" is None` | correct? |
| --- | --- | --- |
| `x = ""` (local, str-typed) | True | no |
| `"" + ""` | True | no |
| `"ab"[0:0]` | True | no |
| a `-> str` function's result | True | no |
| a class FIELD holding `""` | True | no |
| **`["", "x"][0]` (list element)** | **False** | **yes** |
| **`{"k": ""}["k"]` (dict value)** | **False** | **yes** |
| `None is None` | True | yes |
| `"abc" is None` | False | yes |

So the split is exactly **static `AnsiString` vs `Variant`**. `pystr_is_none`
tests `Pointer(s) = nil` and Pascal's empty AnsiString IS a nil handle, so every
statically str-typed operand conflates them. A string boxed in a variant carries
`VT_STRING` in its TAG, and `is None` tests the tag — so **the variant
representation already gets this right today.**

That reframes the decision. "Give None-str a representation `""` cannot collide
with" is not a design to invent: one already exists in this codebase, works, and
is exercised by the corpus.

## Options

### A — route str-typed Optionals through variants (recommended)

Make a `str` value that can be None a variant, as container elements already are.

- **Working precedent in-tree**, which is the strongest argument available: the
  two correct rows above are this option, already shipped.
- Cost: boxing on the Optional paths, and the promotion boundary has to be
  decided (every `str`? only `Optional[str]`? only where a None can reach?).
  Only-Optional keeps the hot plain-`str` path untouched, which matters because
  `s := s + c` performance work is recent and load-bearing.
- Risk: widening a str to a variant is exactly what broke
  `test_nilpy_none_str_field` when tried from a different direction
  ([[bug-nilpy-name-bound-by-a-method-call-in-a-block-is-undefined-later]]), so
  the promotion boundary is the whole design, not a detail.

### B — a distinguished non-nil sentinel handle for None-str

Keep str as AnsiString; make `pystr_none` return a unique non-nil handle that
`pystr_is_none` recognises.

- Smallest change to the type model; the hot path stays an AnsiString.
- Cost: EVERY consumer of a str must treat that handle as not-a-string —
  `Length`, indexing, concatenation, printing, the C boundary. Miss one and it
  renders as whatever bytes the sentinel points at, which is a silent wrong
  value rather than a crash. That is a large audit surface with no compiler help.

### C — make the empty AnsiString non-nil

Fixes it at the root for str, but changes the RTL's string representation for
**Pascal too**, and the self-host binary depends on it. Disproportionate, and it
would be felt by every track. Listed for completeness; not recommended.

### D — document the divergence and close

`""` and None being one value is a real CPython incompatibility on code that
branches with `if s is None:` versus `if s == "":`. By CLAUDE.md's
upward-compatibility rule this is a defect, not a dialect choice — working
CPython code can observe it — so D is only defensible as an explicit deferral,
not as a resolution.

## Recommendation

**A, scoped to `Optional[str]`.** It is the only option whose correctness is
demonstrated rather than argued, and scoping to Optional keeps the plain-`str`
performance path out of it. Decide the promotion boundary explicitly and write it
down, because that boundary — not the representation — is where this will go
wrong.

## Note

`==` is unaffected: `x == ""` already answers True correctly. It is `is None`
specifically that conflates, so any fix can be validated by the `is`/`==` pair
disagreeing the way CPython makes them disagree.
