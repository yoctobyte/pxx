---
summary: "nilpy: songformatter's key_analysis.py COMPILES but segfaults at run time"
type: bug
track: N
prio: 70
---

# key_analysis.py compiles and then segfaults

- **Type:** bug (Nil-Python frontend / runtime) — **Track N**
- **Opened:** 2026-07-27, the moment the module first compiled
  ([[feature-demo-songformatter-pxx-target]]).

## Where it stands

`key_analysis.py` (762 lines, songformatter's key detection) compiles clean:

```
./compiler/pascal26 ~/songformatter/key_analysis.py /tmp/ka
ok: /tmp/ka  [code=1527134B  data=30856B  bss=11692B  procs=987]
```

Running it segfaults. Repro without the cross-module import (NilPy cannot import
a sibling `.py` yet — that is [[feature-nilpy-py-module-loader]]): concatenate
the module and a driver into one file.

```python
# /tmp/ka_all.py = key_analysis.py + this
NOTES = {"C": ["C","E","G"], "F": ["F","A","C"], "G": ["G","B","D"],
         "Am": ["A","C","E"], "Dm": ["D","F","A"], "Em": ["E","G","B"]}
def notes_of(ch: str) -> list[str]:
    return NOTES.get(ch, [])
res = analyze_key(["C","F","G","C","Am","F","G","C"], chord_to_notes=notes_of)
print(res.final.winner.label)   # CPython: C / weighted / 8
```
pxx: compiles, then SIGSEGV with no output.

## Where to start

Compiling was reached through a long run of new machinery in one session, and any
of it could be the cause. In rough order of suspicion:

1. **The runtime method dispatch across eight detector classes** — `detector.analyze(...)`
   now emits an is-test chain over every candidate class (the cap was raised from
   3 to 16 for exactly this file). A wrong arm, or the fallback arm calling the
   statically-picked class's method on another class's instance, would land
   here.
2. **`sorted(..., key=lambda ...)`** — the key is a pyeval CLOSURE invoked per
   element; closure invocation from a compiled program is the newest path in the
   stack.
3. **for-target unpacking** (`for k, v in pairs`) — it binds hidden locals and
   indexes through pyvar_getitem; an element that is not a 2-sequence would
   deref badly.
4. **Dataclass-heavy call chains** — the module builds DetectorResult /
   KeyCandidate objects constantly, and
   [[bug-nilpy-omitted-variant-default-segfaults]] (reading a DEFAULTED variant
   parameter) is already known to crash and is very likely present here.

(4) is the one to rule out first: it is filed, reproduces in three lines, and
this module is full of `def f(..., default=None)` shapes.

## Gate

The module runs and its output matches CPython's for the same chord list, then a
`.npy` regression test covering whichever mechanism turns out to be at fault.
