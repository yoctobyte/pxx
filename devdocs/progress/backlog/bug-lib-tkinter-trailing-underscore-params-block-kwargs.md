---
track: B
prio: 40
type: bug
---

# tkinter facade parameters named with a trailing underscore cannot be passed by name

```python
txt.insert(index="end", chars="HELLO")
```

```
error: Nil Python: Text.insert has no parameter named 'index'
```

The facade declares them with a trailing underscore:

```pascal
procedure insert(const index_: AnsiString; const chars: AnsiString);
procedure delete(const first_: AnsiString; const last_: AnsiString = '');
function  get(const first_: AnsiString; const last_: AnsiString = ''): AnsiString;
```

Positionally these work; by NAME they cannot be reached, and CPython's tkinter
documents `index=` and `first=`/`last=` as the parameter names. The compiled
lambda path binds keyword arguments by name against the real signature, so a
mismatch is now a compile error rather than a silent mis-bind
([[bug-nilpy-pyeval-host-kwargs-positional]]) — which is how this surfaced.

Whatever the underscore was avoiding (`index` and `get` also name methods on the
same or a sibling class), the exported NAME is part of the API and should match
CPython's. If the Pascal identifier has to differ, the frontend needs a way to
carry the Python-visible name — but check first whether the plain spelling
compiles today.

## Where to look

`lib/pcl/tkinter.pas` — census every `_`-suffixed parameter in one pass rather
than fixing the three above, and check `lower_` (a METHOD, same treatment) while
there.

## Gate

`make lib-test` plus a `.npy` calling the renamed parameters by keyword against
CPython's spelling.
