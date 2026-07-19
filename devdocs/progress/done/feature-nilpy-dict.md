---
track: N
prio: 60
type: feature
---

# NilPy: dict v1 — TPyDict

Hangs off [[feature-nilpy-corpus-uforth]] milestone 1. Filed 2026-07-19 after
the ctor-field fix moved uforth's wall from "cannot infer class field type" to
`Nil Python: dict/tuple/set types are not supported yet` (`PyAnnTypeAt`).

## Why now

Dict is the single largest remaining blocker in the uforth census, and it is
load-bearing rather than incidental — `VM.dict` IS the Forth dictionary:

| use | count in uforth.py |
| --- | --- |
| `Dict[...]` annotations | 18 |
| `{}` / `{k: v}` literals | 18 |
| `.get(k[, default])` | 21 |
| `.items()` / `.keys()` / `.values()` | 5 |
| `del d[k]` | 4 |
| `k in d` | 2 (plus `.dict[...]` subscripts, 3) |

Nested forms are real, not hypothetical: `Dict[int, Dict[str, Any]]`
(`block_buffers`, `file_handles`) and `Dict[int, List[Word]]`
(`wordlist_entries`).

## Shape — mirror TPyList exactly

`compiler/builtin/pylib.pas` already has the pattern: a class over a heap
block of 16-byte variant slots, with the frontend desugaring Python syntax
onto its methods. TPyDict = two parallel slot arrays (keys, values) + count.

- Keys are Variants, so `str` and `int` keys both work with one type — which
  is what the corpus needs (`Dict[str, Word]` and `Dict[int, ...]` side by
  side). Key equality = tag-and-payload compare, with the string case
  comparing contents.
- **Linear scan first.** Measured after landing: 2 000 entries build in
  0.01 s, 5 000 in 0.07 s, 20 000 in 1.17 s — textbook quadratic, and
  irrelevant at uforth's scale (VM.dict holds a few hundred words). The hash
  is worth doing when a corpus crosses ~10 000 entries, not before. `VM.dict` reaches a few hundred entries and every
  Forth word lookup hits it, so this WILL want a hash — but correctness
  before speed ([[feedback_correctness_over_optimization]]), and the hash is
  a drop-in replacement behind the same methods. Note the O(n) in the ticket
  when it lands so the follow-up is not a surprise.

Frontend work (`pyparser.inc`):
- `PyAnnTypeAt`: `Dict[K, V]` -> tyClass/TPyDict instead of the current
  clean error. Nested annotations are already skipped by bracket depth.
- `{}` / `{k: v, ...}` literal. **Careful:** `{a, b}` is already parsed as a
  SET literal (`PyParseSetLiteral`) — disambiguate on the first `:` at depth
  1, and an empty `{}` is a dict in Python, not a set.
- Subscript get/set on a dict-typed base, routed like `PyMakeStrIndex`.
- `.get`, `.items`, `.keys`, `.values`, `len`, `in` — `.get` is the big one
  (21 sites) and takes an optional default.
- `del d[k]`.

## Sequencing note

`.items()` returning an iterable is only useful once `for k, v in ...` (tuple
unpack + for-in over a list) lands, which is its own rung. Land the mapping
core first (literal, subscript, get, in, len, del); the iteration methods can
return a TPyList of keys and grow later.

## Gate

`test-nilpy` green (with new `.npy` cases diffed against CPython as the
oracle) + `--tier quick` + self-host byte-identical + `make fpc-check`
(see [[feedback_fpc_bootstrap_advisory_invisible_to_local_gate]]).

## Log
- 2026-07-19 — resolved, commit 77a39b40.
