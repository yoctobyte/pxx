---
summary: "songformatter (the real CPython app) no longer compiles: `set_` no such member on the scrollbar callback, and a get() arity error in settings.py — app unchanged since 2026-07-28"
type: bug
track: N
prio: 60
---

# songformatter stopped compiling — `set_` callback member, and `get()` arity

- **Type:** bug (Track N — Nil Python frontend; possibly Track B for the Tk facade half)
- **Filed:** 2026-08-09 by Track D while verifying a docs claim before publishing it.
- **Owner:** —

## What happens

`~/songformatter` is the real CPython desktop app that drove the 2026-07-29
NilPy bughunt (`devdocs/dev/handoffs/nilpy-songformatter.md`). That handoff
records it reaching "full GUI, song loaded in the editor, redraw and key
analysis actually executing". Today it does not get past the compiler.

```
$ cd ~/songformatter
$ pascal26 SongFormatter.py /tmp/songfmt
pascal26:171: error: "set_": no such member on this record/class
  near: configure  yscrollcommand  bar  >>> set_
```

The construct is `settings.py:132`, reached through `SongFormatter.py:12`
(`from settings import SettingsEditor, get`):

```python
self.canvas = tk.Canvas(self, highlightthickness=0)
self.scrollbar = tk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
self.canvas.configure(yscrollcommand=self.scrollbar.set)
```

Note `bar` and `set_` in the error text: the reported member is not the source
member. `scrollbar` appears truncated to `bar` and `.set` has become `set_`.

Compiling that module on its own surfaces a **second, different** failure:

```
$ pascal26 settings.py /tmp/settings_only
pascal26:210: error: Nil Python: get() takes exactly 2 argument(s), got 0
  near:  var  get   >>>
```

## Why this is worth a ticket rather than a shrug

**The app has not changed.** `git log --since=2026-07-29` in `~/songformatter`
is empty; its last commit is 2026-07-28, the day before the handoff recorded it
running. So either the frontend regressed since then, or the 07-29 session
never compiled this module and the handoff overstates how much of the app
built. Both are worth knowing, and the tstate history should be able to
distinguish them.

Reproduces identically on the pinned stable compiler and on a `master` build
from 2026-08-09 18:48, so it is not a stale-binary artifact.

## What is NOT the cause (checked, so nobody re-walks it)

The obvious theory — `set` is a Pascal keyword, so the frontend mangles the
member to `set_` — does not survive a minimal repro. All three of these
**compile and run cleanly**:

1. a user-defined class with a `def set(self, x: int)`, called normally;
2. the same method passed by reference to another function and invoked there;
3. `tkinter.Scrollbar.set` passed as `canvas.configure(yscrollcommand=bar.set)`,
   both at module level and as `self.scrollbar.set` inside a `tk.Frame`
   subclass — i.e. the exact shape of the failing line.

So the trigger is something the isolated cases do not have: the real file mixes
`import tkinter as tk` with `from tkinter import BooleanVar, StringVar`, has a
deeper class hierarchy, and fails only via the cross-module import path. Start
by bisecting settings.py rather than by trying to reproduce from the snippet.

## Acceptance

`pascal26 SongFormatter.py` builds, and the result runs far enough to open the
settings editor. The `get()` arity error is likely a separate defect in the same
file — split it out if it turns out to be unrelated.

## Log
- 2026-08-09 — filed by Track D. Found while checking whether "Nil Python
  compiles real-world applications" could go into `docs/**`: the claim is true
  of what the handoff recorded and is NOT reproducible today, so it was kept
  out of the docs and filed here instead.
