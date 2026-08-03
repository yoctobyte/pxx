---
prio: 70
track: N
type: bug
summary: "a def whose body is a FORWARD call loses its annotated class result, so attribute access on the call no longer parses"
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_class_return.npy red at cd891b44a616 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). **Triaged and bisected by T on 2026-08-04; the fix is Track N's** — T owns the tool, never the bug.
- **Found:** 2026-08-03T22:59:39Z
- **Test source:** test/test_nilpy_class_return.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_class_return.npy'` at cd891b44a6168085220aeeeb481b79885a679cdd

## Range
bad `cd891b44a616`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:63: error: unexpected token
(tail)
Expected: ), but got:  (Kind: 81, Line: 63)
pascal26:63: error: unexpected token
  near:    build_later   >>>  name  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (Track T, 2026-08-04)

**Bisected to `86b0fc2b7` — "fix(nilpy): a def's result follows the body, not
the annotation"** (landed 2026-08-04 00:41). Built the compiler from source at
that sha and at its parent, ran the test with each:

| sha | result |
|---|---|
| `86b0fc2b7^` | PASS |
| **`86b0fc2b7`** | **FAIL** |
| `37ce259f9^` (next nilpy commit's parent) | FAIL |
| HEAD | FAIL |

Done by hand because the ledger has **0 commits in range**: this run's
`parent_tested` IS the tested sha (the two-phase watcher re-testing one commit
at a widening tier — test-nilpy is in `full`/`limited`, not `native`), so no
idle bisect would ever have narrowed it.

Not the neighbouring suspects, both excluded by the table above: `37ce259f9`
(the *other* nilpy commit in the window) and the pinned-vs-built compiler
question — the watcher's binary was a genuine build (`compiler_sha256`
`e340e500d9…`, not `pinned`'s `60758ce6ed…`), so this is not the stale-seed
trap.

## Minimal repro — 13 lines, and the trigger is call ORDER

```python
class P:
    def __init__(self, n: str) -> None:
        self.name = n


def build_later() -> P:
    return named_p()


def named_p() -> P:
    return P("late")


print(build_later().name)
```

```
pascal26: error: unexpected token
  near:    build_later   >>>  name
```

**Move `named_p` ABOVE `build_later` and the identical program compiles and
prints `late`.** So it is not the annotation, the class, or the attribute — it
is that the callee is defined *after* the caller.

CPython prints `late` for both orderings, so the pre-`86b0fc2b7` behaviour was
the correct one here.

## Hypothesis for the owning track (N), not a conclusion

Making the result follow the BODY is right for the bug that commit fixed, but on
a forward edge the body's type is not resolved yet at the point the caller is
parsed — so the result appears to have no class identity and `.name` fails at
parse time rather than resolving against `P`. The annotation is the only type
information available at that moment; it looks like it now needs to be the
fallback when the body is not yet known, rather than being dropped outright.

The test that caught this (`test/test_nilpy_class_return.npy`) covers exactly
this case — the forward-call lines were added 2026-07-20 by `32c3894ae`
("cover FORWARD CALLS between top-level defs"), so the coverage was already
there and did its job.
