---
prio: 55
track: N
type: bug
blocked-by: []
summary: "convertrawtext.py and SongFormatter.py fail at key_analysis.py:82 (`tonic, mode = label.split(\" \", 1)`) with `unexpected token`. Pre-existing, was hidden behind the grid keyword-call refusal. Does NOT reproduce standalone or through a plain from-import — needs more of convertrawtext.py's context, not yet minimised."
status: new
owner: ""
---

# A later wall at key_analysis.py:82 blocks convertrawtext.py and SongFormatter.py

- **Type:** bug — Track N. Filed 2026-08-30 by frankwasm out of
  [[feature-demo-songformatter-pxx-target]].
- **Pre-existing, not a regression.** See the attribution below; this was
  simply behind
  [[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]]
  until that landed.

## What happens

```
pascal26:82: error: unexpected token
  near: label  split     >>>
Expected: ), but got:  (Kind: 2, Line: 82)
```

The line is in `key_analysis.py`, not in the file being compiled:

```python
def _key_label_to_parts(label: str) -> tuple[str, str]:
    if label.endswith("m") and " " not in label:
        return (label[:-1], "minor")
    if " " in label:
        tonic, mode = label.split(" ", 1)      # <- line 82
        return tonic, mode
    return (label, "major")
```

Note the reported line number belongs to an **imported module**, so it is not
on the same scale as the line numbers of the file on the command line. Reading
it as "the failure moved earlier in convertrawtext.py" is wrong, and is what it
looks like at first glance.

## Attribution — pre-existing, measured

Compilers built from the same base, one with and one without the keyword-call
fix that unblocked the earlier wall:

| compiler | convertrawtext.py (tuple pads neutralised in a copy of the app) |
| --- | --- |
| `f8f879988222` — **without** the fix | `82: error: unexpected token` |
| `bcb428ba25ac` — with the fix | `82: error: unexpected token` |

The copy has every `padx=(a, b)` / `pady=(a, b)` rewritten to its first element,
which removes the earlier refusal so the **baseline** can reach the same depth.
Both compilers then fail identically. Without that step the baseline stops at
the grid call and never reaches this, which is the whole reason the wall looks
new.

## What does NOT reproduce it

All of these compile clean, on both compilers:

- `key_analysis.py` on its own
- `import key_analysis`
- `from key_analysis import analyze_key` (the spelling `convertrawtext.py` uses)
- `from settings import get, set, getF, getI` followed by the above
- the `_key_label_to_parts` shape extracted on its own

So it needs more of `convertrawtext.py`'s context than any of these carry, and
**it is not minimised**. That is the first job on this ticket; the shape above
is where to start, not a diagnosis.

## A second, probably separate observation from the same file

`convertrawtext.py:1387` rebinds the imported module's own name as a variable
(`key_analysis = analyze_song_key(...)` alongside `from key_analysis import
analyze_key`). Reduced to:

```python
from key_analysis import analyze_key
def f(song):
    key_analysis = analyze_key(song)
    return key_analysis
```

→ `no overload of analyze_key matches these arguments`, **identically on both
compilers**, so also pre-existing. It is probably NOT about the name reuse: the
same shape against a throwaway module (`from mymod import analyze` with a local
named `mymod`) compiles and matches CPython. Something about `analyze_key`'s own
signature is what the overload probe rejects. Recorded here rather than filed
separately until one of the two is minimised, in case they turn out to be one
defect.

## Impact

`settings.py` and `key_analysis.py` compile. `convertrawtext.py` and
`SongFormatter.py` do not, so this is the current wall for
[[feature-demo-songformatter-pxx-target]]. `render_backend.py` is blocked by a
different animal — [[bug-nilpy-render-backend-py-compile-does-not-terminate]] —
which is no answer rather than a wrong one.
