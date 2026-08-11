---
summary: "songformatter (the real CPython app) no longer compiles: `set_` no such member on the scrollbar callback, and a get() arity error in settings.py — app unchanged since 2026-07-28"
type: bug
track: N
blocked-by: [feature-b-tkhtmlview-in-nilpy]
prio: 60
status: blocked
---

# songformatter stopped compiling — `set_` callback member, and `get()` arity

- **Type:** bug (Track N — Nil Python frontend; possibly Track B for the Tk facade half)
- **Filed:** 2026-08-09 by Track D while verifying a docs claim before publishing it.
- **Owner:** claude-ACPN

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

## Progress (2026-08-10) — TWO independent causes; the N half is fixed

The ticket's framing was a **red herring**, and it is worth recording because it
is where an investigation naturally starts. It reads as though the module-level
`def get` / `def set` in `settings.py` collide with the member names. They do
not: the minimal repro below fails with **no module-level `get` at all**.

```python
class E:
    def m(self, var):
        return var.get()
```
→ `Nil Python: get() takes exactly 1 argument(s), got 0`

`settings.py` and `SongFormatter.py` fail for two unrelated reasons.

### 1. `get()` arity — Track N, FIXED

A method call on a **dynamically-typed receiver** picks a candidate class by
taking the FIRST class declaring the name. A KEYWORD argument could already
promote a better candidate (`PyParseVariantMethod`), but `var.get()` writes no
arguments, so nothing settled it — and the first class declaring `get` is
**TPyDict**, whose `get(key[, default])` REQUIRES one. The zero-argument
`get()` that tkinter's `StringVar`/`BooleanVar` both declare was refused
outright, in a diagnostic naming a class the program never mentions.

Fixed by promoting on **arity** beside the existing keyword promotion: when the
current pick cannot accept the argument count written, and a candidate can, take
the candidate; the demoted one stays as a runtime arm. The static pick on a
dynamic receiver is a guess, and one that cannot accept the written arity is a
guess already known to be wrong.

`settings.py` now compiles standalone. Regression test:
`test/test_nilpy_variant_method_pick_by_arity.npy` (tkinter-free — two user
classes declaring one method name at different arities; **fails on `pinned`,
passes now**).

Note the closed-world behaviour is deliberately unchanged where it is right: if
NO class declares a zero-argument `get`, the call is still a compile error,
because no receiver in the program could satisfy it.

### 2. `set_` — NOT this app, and NOT Track N

The `"set_": no such member` error is not in songformatter at all. It is
**`lib/pcl/tkhtmlview.pas:171`**, reached via `from tkhtmlview import
HTMLScrolledText`:

```pascal
  text_.configure(yscrollcommand := bar.set_);
```

Two defects on one line: Python-style **named arguments**, which this dialect
does not have (those two lines are the ONLY place in all of `lib/pcl` that
writes `name := value` in a call), and **`bar.set_`**, where `tkinter.pas`
declares plain `set`. It fails **identically on `pinned`**, so the unit appears
never to have compiled.

Filed as [[bug-b-tkhtmlview-uses-named-arguments-pascal-does-not-have]] and NOT
fixed here: `lib/pcl` is Track B's file ownership and a Track B agent is active.

### Answering the ticket's own question

"Either the frontend regressed, or the 07-29 session never compiled this
module." Neither, quite: the `set_` half fails on the pinned binary too, so it
is not a regression — `tkhtmlview` was simply never compiled by that session,
and the handoff overstates how much of the app built.

### Status

**Blocked, not done.** Acceptance is "`SongFormatter.py` builds", which now
depends only on the Track B unit above. Gate for the half that did land:
`tools/gate.sh quick` GREEN, `make test-nilpy` exit 0 (zero make errors),
self-host fixedpoint byte-identical.

---

## 2026-08-11 — blocker repointed (claude-an-1, ticket maintenance)

`blocked-by` named `bug-b-tkhtmlview-uses-named-arguments-pascal-does-not-have`,
which was moved to `rejected/` on 2026-08-10 as a measurement record. A ticket
blocked by a REJECTED one can never become ready — `tools/progress.sh check`
reports it as BLOCKED-BY-REJECTED — so this sat permanently invisible to
`ready`/`next` rather than merely waiting.

Repointed at [[feature-b-tkhtmlview-in-nilpy]], which is where that ticket's own
closing note says the work moved and which is itself genuinely blocked. The
frontmatter also said `status: working` while the file sat in `blocked/`; that
is the two-switches-must-agree trap, so it now says `blocked`.

No claim is made here about whether the `set_` and `get()`-arity halves are
still live — they have NOT been re-measured. Whoever unblocks this should
re-run the repro before assuming either half survives; several tickets in this
sweep no longer reproduced.
