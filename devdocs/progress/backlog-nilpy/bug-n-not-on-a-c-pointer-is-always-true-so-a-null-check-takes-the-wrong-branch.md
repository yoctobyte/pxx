---
slug: bug-n-not-on-a-c-pointer-is-always-true-so-a-null-check-takes-the-wrong-branch
track: N
prio: 75
type: bug
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "`not p` on a C pointer is TRUE for a non-NULL pointer. `if p` is correct on the same value in the same program, so the truthiness conversion exists and `not` does not use it. Silent wrong branch on the idiomatic null check -- `if not handle: raise` fires after a call that SUCCEEDED. Cost a session: lekkerzeilen's pxx backend reported `SDL_CreateWindow failed` with an empty SDL_GetError while the window had been created."
---

# `not` on a C pointer is always True

```python
import "/usr/include/SDL2/SDL.h"

SDL_Init(SDL_INIT_VIDEO)
w = SDL_CreateWindow("t", 0, 0, 64, 48, SDL_WINDOW_OPENGL)   # succeeds, non-NULL
```

| expression | pxx | correct |
| --- | --- | --- |
| `w != 0` | True | True |
| `w == 0` | False | False |
| `"then" if w else "else"` | **then** | then |
| `not w` | **True** | **False** |
| `not (w != 0)` | False | False |

Measured at `120eeb39f`, binary `7cf02ff177ca`, repro compiled with
`-dSDL_DISABLE_IMMINTRIN_H`. The NULL case (`not n` on a NULL pointer) answers
True, which is right — so the operator is not inverted, it is **constant**.

## Why this one is worth its prio

`if not p:` is THE null check in Python-shaped C interop, and this makes it
fire on success. Nothing errors, nothing warns, and the program reports a
failure that did not happen — the expensive shape CLAUDE.md describes, a
plausible wrong value far from the cause.

It cost a session directly. `lekkerzeilen/platform/_pxx.py` has

    handle = SDL_CreateWindow(title, ..., flags)
    if not handle:
        raise _error("SDL_CreateWindow failed")

and raised that every time, while a probe in the same function printed
`retry handle truthy: True` one line earlier. **`SDL_GetError()` was empty,
which was the instrument telling the truth and being read as a second
failure** — an error path reached without an error. Three hypotheses were
measured and discarded first (the tuple default `gl_version=(3, 3)` unpacking,
the `open_window = _backend.open_window` alias, and the window flags and
position constants, all three of which were correct) because the one thing
nobody doubts is a `not`.

`if p` being right is what hides it: the same file has working truthiness a few
lines away, so the construct looks supported.

## Where to look

The `not` arm of the NilPy unary-operator lowering, versus whatever the
conditional/branch path uses to test a value for truth — the branch path has a
pointer case and `not` does not reach it. Likely candidates are a `not` that
assumes a Boolean operand and emits a Boolean complement against a value that
is a pointer width, or one that tests a tag rather than the value.

**The population IS just the pointer — table written, and it aims the fix.**
`not` was measured against CPython over every other operand type and agrees on
all 18 rows: `True`/`False`, `0`/`1`/`-1`, `0.0`/`2.5`, `''`/`'x'`, `[]`/`[1]`,
`{}`/`{'a':1}`, `None`, and each of int/str through a variable rather than a
literal (so the constant folder is not what is being tested). So this is not a
broken `not` — it is a `not` with **no C-pointer case**, and everything native
is correct. Fix the missing case; do not touch the working ones.
