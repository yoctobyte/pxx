---
track: N
prio: 45
type: bug
blocked-by: []
---

# `&`/`|`/`-`/`^` on sets, `|` on dicts silently did raw pointer arithmetic

Found by proactive CPython-diff sweeping (not a pre-existing ticket). NilPy
represents a Python `set` identically to a `list` (a `TPyList`, built with
`.add()`'s duplicate-skipping insert instead of `.append()` — there is no
separate "IsSet" runtime tag). Because neither of NilPy's two independent
binary-operator dispatch chains treated `TPyList`/`TPyDict` operands specially
for `&`/`|`/`-`/`^`, these fell through to plain integer/pointer bitwise
codegen — silently computing garbage on the two class-handle values instead of
set intersection/union/difference/symmetric-difference or dict union.

## Root cause: two independent binop dispatch paths

NilPy's binop typing/lowering is split across two code paths that do not share
dispatch:
- `compiler/parser.inc` — the shared Pascal/NilPy binop chain (handles `+`/`-`
  arithmetic, and is where existing NilPy class-typed dispatch like
  list-concat/bytes-concat lives, gated on `PyExprMode`).
- `compiler/pyparser.inc` — NilPy's own dedicated bitwise-operator precedence
  chain, `PyParseBitAnd`/`PyParseBitXor`/`PyParseBitOr` (`&`/`^`/`|`
  respectively), which builds `AN_BINOP` nodes directly and never touches
  parser.inc's logic.

A fix landed in only one silently misses the operators owned by the other
(confirmed empirically: patching only parser.inc fixed `-` but left `&`/`|`/`^`
still doing raw arithmetic, since those three are lexed via pyparser.inc's own
chain).

## Fix

- `compiler/builtin/pylib.pas`: added `pyset_and`/`pyset_or`/`pyset_sub`/
  `pyset_xor` (`TPyList, TPyList -> TPyList`, built via the existing
  `pycontains` membership helper) and `pydict_or` (PEP 584 union via
  `keylist`/`fetch`/`store`, `d2` wins key collisions, `d1`'s order first).
- `compiler/parser.inc`: added `PyNodeIsPyDict`/`PyMakeDictBinCall` forward
  decls and a `PyExprMode`-gated dict-`|` / set-`&|−^` dispatch branch in the
  shared binop chain (covers `-`, and anything else that reaches this path).
- `compiler/pyparser.inc`: added `PyNodeIsPyDict`/`PyMakeDictBinCall`
  (mirroring the existing `PyNodeIsPyList`/`PyMakeListBinCall`), and rewrote
  `PyParseBitAnd`/`PyParseBitXor`/`PyParseBitOr` to check for
  set/dict-typed operands (via `PyNodeIsPyList`/`PyNodeIsPyDict`) BEFORE
  calling `PyBitGuard`/building a raw `AN_BINOP` — this is the path that
  actually owns `&`/`|`/`^` for NilPy source.

Verified all four set operators and dict `|` produce CPython-matching values
(only a separate, out-of-scope cosmetic gap remains: a set currently prints
with `[...]` list brackets, not Python's `{...}` — there's no runtime "is a
set" tag to key display on). New regression test `test/test_nilpy_set_ops.npy`
(gated in `test-nilpy`), diffed directly against CPython's own output.

While regression-testing this fix, found `a & b` on boolean-typed *variables*
(not just set/dict operands) unconditionally rejected by `PyBitGuard` — checked
against a pre-fix binary (`git stash` + rebuild) and confirmed this is a
**pre-existing, unrelated** limitation, not something this change introduced.
Filed separately as
`bug-nilpy-bitwise-op-rejects-boolean-variable-operand`.

`tools/testmgr.py --tier quick` green; self-host confirmed byte-identical via
`make pxx-debug` after each of the two rebuild cycles (parser.inc alone, then
+ pyparser.inc).

## Log
- 2026-07-31 — resolved, commit HEAD.
