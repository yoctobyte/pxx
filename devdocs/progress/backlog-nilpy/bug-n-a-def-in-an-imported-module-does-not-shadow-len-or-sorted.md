---
slug: bug-n-a-def-in-an-imported-module-does-not-shadow-len-or-sorted
title: a def in an imported module does not shadow len or sorted
summary: >
  A module-level `def len(x)` in an imported `.py` module is not reached by a
  bare `len(...)` inside that same module: the call SEGFAULTS. A module-level
  `def sorted(x)` in the same position silently reaches pylib's `sorted` and
  answers `[]`. Both are pre-existing and unaffected by the fix for
  bug-n-a-def-in-an-imported-module-does-not-shadow-a-builtin, which repaired
  the same shape for `format`, `str` and `open`; the two names here go through
  a different lowering.
track: N
type: bug
prio: 55
owner: unassigned
status: open
---

## Repro

`mn.py` next to the main program, reached with `-Fu`:

```python
def len(x):
    return "USER"


def caller(x):
    return len(x)
```

```python
import mn
print(mn.caller("abcd"))
```

| name defined in the module | pinned v409 | HEAD (after the shadow fix) | CPython |
| --- | --- | --- | --- |
| `len` | **SIGSEGV** | **SIGSEGV** | `USER` |
| `sorted` | `[]` | `[]` | `USER` |
| `format` | `abcd` | `USER` | `USER` |
| `open` | `FileNotFoundError` | `USER` | `USER` |
| `str` | `abcd` | `USER` | `USER` |
| `abs`, `max` | `USER` | `USER` | `USER` |

Measured 2026-09-14 with `compiler/pascal26` at the commit that fixed the
neighbouring ticket, and with `stable_linux_amd64/default/stable_pinned` as
the control. The four rows that CHANGED are the fix; the two that did not are
this ticket.

## What is known

`PyUserShadowsProc('len')` answers **TRUE** in the module now
(`PXXDBG=n.shadow` confirms `user=TRUE nilpyuser=TRUE curunit=669`), so the
`len` intercept arms at `pyparser.inc:50331` and `pasparser_expr.inc:2778`
both stand down correctly. The AST for `caller` then holds a plain `AN_CALL`
with `tk=22` (AnsiString) — the user's return type — so the parser has bound
the right thing. The IR, however, is two calls and neither is the user's:

```
2: lea a=543 ... [sym=x]
3: arg a=2 tk=22
4: call a=1190 b=3 tk=13
5: arg a=4 tk=22
6: call a=1188 b=5 tk=13
```

So the failure is BELOW the parser, in whatever rewrites a `len` call once the
intercepts have declined — which is also the reason the identical program in
the MAIN `.npy` works (`def len(x)` + a bare `len(x)` there answers `-1`
correctly, both pinned and at HEAD). Start by finding what else is keyed on
the name `len` after `PyParseFactorCore`.

`sorted` is the quieter half and probably a different site again: it produces
a correct-looking empty list rather than a crash, which is the
`bug-n-...-returns-an-empty-aggregate` collision this repo's own rules warn
about — a probe whose expected value is `[]` cannot see it.

## Gate

`make test-nilpy` plus two rows added to
`test/test_nilpy_a_def_in_an_imported_module_shadows_a_builtin.npy` (the
fixture deliberately omits `len` and `sorted` today and says so in its
module docstring).

## Log
- 2026-09-14 — split out while fixing the `format` half. Not merged into that
  ticket on purpose: the four names that were repaired and the two that were
  not go through different lowerings, and merging them would let the green
  half certify the red one.
