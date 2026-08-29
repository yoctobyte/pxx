---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`import tkinter` then `import configparser` fails to compile: tkinter.pas's `Text = class(Widget)` captures configparser.pas's `var f: Text` (the RTL file type), so `Assign(f, path)` sees (class, AnsiString). Swapping the two imports compiles. Pure Pascal `uses tkinter, configparser` is clean in BOTH orders — so the unit scoping that bug-pascal-uses-is-transitive fixed for `uses` was never inherited by NilPy's import path. Two-line repro; blocks three of songformatter's five modules."
status: new
owner: ""
---

# NilPy import order leaks a class name into a later-compiled RTL unit

- **Type:** bug (Nil Python frontend — unit/import scoping) — **Track N**.
- **Filed:** 2026-08-29 by the wasm lane while re-measuring
  [[feature-demo-songformatter-pxx-target]] against pin v392 (`60b060bb54a8`).

## Repro

```python
import tkinter
import configparser
print("ok")
```

```
pascal26:354: error: no overload of Assign matches these arguments
  argument types: (class, AnsiString)
  candidates:
    Assign(record, AnsiString)
  in: lib/rtl/configparser.pas
```

Swap the two lines and it compiles.

## Cause

`lib/pcl/tkinter.pas:312` declares `Text = class(Widget)` — the Tk text widget.
`lib/rtl/configparser.pas:350` declares `var f: Text` meaning the RTL's file
type, and then calls `Assign(f, path)` / `Reset(f)` / `Eof(f)` on it. When
tkinter is imported first, its class is already in the flat class namespace and
captures the name, so every file operation in `ConfigParser.read` and
`.write` fails to match.

## The control is what makes this Track N and not another instance of the flat namespace

Pure Pascal does NOT reproduce it, in either order:

| program | result |
| --- | --- |
| `uses tkinter, configparser` | **OK** |
| `uses configparser, tkinter` | **OK** |
| `import tkinter` / `import configparser` (NilPy) | **fails** |
| `import configparser` / `import tkinter` (NilPy) | OK |

[[bug-pascal-uses-is-transitive]] is **done**, and the two Pascal rows are that
fix working: a unit's classes no longer leak into a sibling compiled after it.
The NilPy import path did not inherit it. So this is not a re-litigation of
[[decide-class-namespace-scoping]] — that fork was resolved-by-cause on the
grounds that proper unit-scoped `uses` dissolves it, and for Pascal it did.
This is the same fix missing on the other frontend's path.

## This is NOT a reopening of [[bug-a-tkinters-text-class-captures-the-rtl-text-record-in-other-units]]

That ticket is in `done/`, fixed at `8c8a95a69` ("the class-over-record
preference obeys unit visibility"), and its title matches this symptom exactly:
same `Text` class, same `configparser.pas`, same `Assign` error text. Its repro
is five lines of pure Pascal:

```pascal
program cp3;
uses tkinter, configparser;
begin
  WriteLn('both ok');
end.
```

**That repro passes today.** So does the reverse order. Both rows in the table
above are that fix working, and they are in this ticket precisely so the next
reader does not open the closed ticket, recognise the symptom, and conclude the
question is settled. A closed ticket that matches your symptom is worse than an
open one: an open one gets re-read, a closed one closes the question.

What is left is the half that fix did not reach — NilPy's `import`, which does
not go through the Pascal `uses` path and did not inherit its unit visibility.
The two-line Python repro at the top fails on a tree where the five-line Pascal
repro passes, which is the whole claim, and it is the reason this is filed in N
rather than reopened in A.

## Not the name `Text`, and not the `from` list

Worth recording because the obvious theory is wrong twice:

* `from tkinter import Text` looks like the culprit and is not. `from tkinter
  import Frame` — naming a completely different class — fails identically,
  because the whole unit is compiled either way.
* `import tkinter as tk` and plain `import tkinter` both fail. The alias is not
  involved.

The trigger is *any* import of tkinter before configparser.

## Impact

Three of songformatter's five modules stop here: `convertrawtext.py`,
`SongFormatter.py` (both import tkinter at the top and reach configparser
through `settings.py`), and it is the first wall for the application as a whole.
Reordering imports is an app-source edit, which this track's mission forbids —
songformatter's whole point is compiling unmodified CPython source, and CPython
does not care about import order here.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical, plus the two-line
repro above compiling in both orders, plus the two Pascal control rows staying
green so the fix is not bought by re-breaking `uses`.
