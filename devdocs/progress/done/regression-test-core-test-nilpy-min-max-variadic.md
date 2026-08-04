---
prio: 70
status: done
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_min_max_variadic.npy red at 9305672dbcd5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-04T03:59:18Z
- **Test source:** test/test_nilpy_min_max_variadic.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_min_max_variadic.npy'` at 9305672dbcd5f66880058f28120d237032e6fedc

## Range
bad `9305672dbcd5`, last good `c51086424657`, 3 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:5: error: no overload of min matches these arguments
(tail)
pascal26:5: error: no overload of min matches these arguments
  argument types: (Integer, Integer, Integer)
  candidates:
    min(Int64, Int64, Int64, Int64, Int64)
  near:       >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Fixed 2026-08-04 (claude-AN — author of the offending commit)

Caused by `8a660bce7`, "a def shadowing a builtin is registered at all". That
commit made `PyRegisterDefShells` register a shell for a def whose name only
exists in a UNIT — necessary, because otherwise `def len(x)` was never
registered and no shadowing could work at all. But a shell exists from the top
of the module, and this test encodes the rule that makes that wrong:

```python
print(min(3, 1, 2))                       # CPython: 1 — the BUILTIN
...
def min(a, b, c, d, e) -> int: return 100
print(min(1, 2, 3, 4, 5))                 # CPython: 100 — the user's
```

**Python rebinds a name when the `def` STATEMENT runs**, so a call ABOVE the def
still reaches whatever the name meant before. With the shell visible from the
top, `PyUserShadowsProc` answered True for the earlier calls too, the overload
demote dropped every pylib `min`, and `min(3, 1, 2)` was left with no candidate
at all — "no overload of min matches these arguments … candidates: min(Int64 ×5)".

The test was right and the compiler was wrong; the expectation was not touched.

### Fix: carry the def's POSITION

Reverting the shell would have re-broken `len` (without a shell the name is not
visible at all — measured: `len([1,2])` went back to the builtin). Both rules
hold together instead:

- `ProcPyDefTok[]`, a parallel array beside `ProcUnitIdx`/`ProcHdrTok`
  (per [[project_tsymbol_field_landmine]] — a parallel array, not a `TProc`
  field), records the token index of every NilPy module-level `def`;
- `PyUserShadowsProc` accepts a main-program candidate only when its
  `ProcPyDefTok` is 0 (everything that is not a NilPy module def) or at or
  before the current call site.

Deliberately NOT `ProcHdrTok`: that field is compared against `CurBodyHdrTok`
under `RequireForward` and means a different thing.

### Verified

`test_nilpy_min_max_variadic` diffs identical to CPython again, and so do all
fifteen tests touched today, re-run individually against the oracle —
including the `len` shadowing this had to keep working. `tools/gate.sh quick`
GREEN, self-host byte-identical.

Note the loop that caught it: the shadowing commit gated green on quick, and
`test-core` is a full-tier job, so the watcher found it and pinned the bad sha
within the hour. Working as designed.
- 2026-08-04 — resolved, commit a6754ddf7.
