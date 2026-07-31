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

## RESOLVED 2026-07-31 — the plain spelling compiles, so the API now carries it

Measured first, as the ticket asked. PXX parses a MEMBER name contextually, so a
method or parameter may be called `set`, `file`, `destroy` or `lower` even though
Pascal reserves or overloads those words — a two-program probe confirmed it
before anything was renamed. Nothing needed a frontend change.

Renamed to CPython's own spelling, in one census pass:

| was | now | where |
| --- | --- | --- |
| `index_`, `first_`, `last_` | `index`, `first`, `last` | `Text.insert` / `delete` / `get` / `tag_add` |
| `path_` | `path` | `Notebook.nametowidget` |
| `file_` | `file` | `PhotoImage.Create` |
| `lower_` | `lower` | `Widget` |
| `destroy_` | `destroy` | `Widget` |
| `set_` | `set` | `Scrollbar`, `StringVar`, `BooleanVar`, and `lib/rtl/configparser.pas` |
| `orient_` | `fOrient` | `Scrollbar` — an INTERNAL field, not part of the API; the Pascal `f`-prefix says so |

The frontend's trailing-underscore fallbacks (`parser.inc` for the typed path,
`pyparser.inc` for the variant path) are now a legacy compatibility route rather
than the way these names are reached. They are left in place; nothing depends on
them here any more.

### What stays underscored, and why

`END_` (and `X_` / `Y_` next to it) are module CONSTANTS, not members, and a
const block is parsed as a declaration list — a const literally named `END` ends
the block, and every constant after it silently disappears (that is how
`tk.CENTER` once came back undefined). Verified again with a probe. The qualified
Python spellings `tk.END` / `tk.X` / `tk.Y` already resolve through the
frontend's mapping, so the application still writes CPython's name; only the
Pascal-side identifier differs, at a declaration that documents why.

### Fallout found and fixed

`examples/tk/callbacks.npy` DIED at runtime — `'Scrollbar' object has no
attribute 'set'`. The underscore fallbacks both guard on "a call follows", so a
bound method taken as a VALUE (`yscrollcommand=self.bar.set`, the ordinary way a
scrollbar is wired) never reached `set_`. With the method named `set`, the
example runs: it is now asserted in `lib-test`, output and all, rather than
merely compiled.

### Gate

`tools/gate.sh lib` GREEN. New regression `examples/tk/kwargs.npy` — every
renamed parameter passed BY KEYWORD, plus `set`/`lower`/`destroy` called by
CPython's name — asserted in `lib-test`'s `tk-nilpy` step under Xvfb, alongside
`callbacks.npy`'s full output.

## Log
- 2026-07-31 — resolved, commit 2c9dc2317.
