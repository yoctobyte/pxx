---
track: A
prio: 55
type: bug
summary: "NilPy resolves the class name `Text` to lib/rtl/textfile.pas's `Text = record` (the FILE type) instead of tkinter.Text, in the two positions that record a type by NAME — an instance attribute and a base class. Locals and globals resolve correctly. Blocks any NilPy code that stores or subclasses a Text widget"
status: done
owner: claude-AN
---

# NilPy: `Text` as an attribute or base class binds the RTL file record

- **Type:** bug (NilPy name resolution) — **Track A** file ownership
  (`compiler/parser.inc` attribute typing / the shared class lookup), Track N
  facing. Same shape and split as
  [[feature-nilpy-import-a-py-module-from-the-library-path]].
- **Opened:** 2026-08-10 by Track B, porting [[feature-b-tkhtmlview-in-nilpy]].
  Found before writing the port, which is the point: the port is a Text-based
  widget, so this is its core, not an edge.
- **Measured on** `stable_linux_amd64/default/pinned` (Track B never rebuilds
  the compiler), `-Fulib/pcl`, under `DISPLAY=:99`.

## The collision

`lib/pcl/tkinter.pas:302` declares `Text = class(Widget)`. `lib/rtl/textfile.pas:14`
declares `Text = record` — standard Pascal's FILE type. One flat class
namespace, first match wins, and the file record wins.

This is a live residue of [[bug-pascal-uses-is-transitive]], which is **done**.
That fix is not enough for these two positions, which is the news here. The
Pascal source of `lib/pcl/tkhtmlview.pas` knew about the collision and dodged it
by hand — `text_: TkTextWidget` with the comment *"the RTL's `Text` is a FILE
record and wins an unqualified lookup outside tkinter"*. NilPy has no such alias
to reach for, because the application writes the Python name.

## What works and what does not — one cause, three faces

`Canvas` and `Scrollbar` are the controls: same façade, same positions, no RTL
name collision, and they behave correctly throughout.

| position | `Text` | control (`Canvas`/`Scrollbar`) |
| --- | --- | --- |
| local / global — `t = Text(root, …)`, `t.insert(…)` | **works** | works |
| instance attribute — `self.t = Text(…)` | **falls back to DYNAMIC** | statically typed |
| qualified attribute — `self.t = tk.Text(…)` | **compile error** | works |
| base class — `class H(Text)` / `class H(tk.Text)` | **wrong base** | works |

The type is recorded correctly wherever it is resolved once and kept (a local),
and incorrectly wherever it round-trips through the bare NAME (an attribute's
inferred type, a base-class reference).

**Face A — attribute becomes dynamic.** `self.text = Text(self, …)` compiles,
and direct calls work, because dynamic dispatch finds the façade method by name
at run time. The proof it is dynamic rather than typed is the *diagnostic*, not
a guess — an unknown method on each:

```
self.bar.nosuchmethod()   -> "Nil Python: Scrollbar has no method nosuchmethod"      (STATIC, closed world)
self.text.nosuchmethod()  -> "Nil Python: no class declares a method or callable
                              field .nosuchmethod()"                                 (DYNAMIC, searched everywhere)
```

The consequence is the one that matters: a **bound method as a VALUE** fails at
run time off a dynamic receiver, while a direct call succeeds.

```python
self.text.yview("moveto 0")            # works    — direct call, dynamic dispatch
self.bar.config(command=self.text.yview)   # AttributeError: 'Text' object has no attribute 'yview'
```

That second line is the canonical scrollbar wiring, so **a scrolled Text cannot
be expressed at all**. The same line against a `Canvas` receiver works.

**Face B — wrong base class.** Both spellings, and the control beside it:

```python
class H(Text):     ...   # "Nil Python: H has no method insert"
class H(tk.Text):  ...   # "Nil Python: H has no method insert"
class G(tk.Canvas): ...  # works: G().yview("moveto 0") runs
```

`H` inherits the file RECORD, which has no methods. This is the shape real
tkhtmlview uses (`HTMLScrolledText(ScrolledText)` → `Text`), so it is not an
exotic spelling.

**Face C — qualified attribute is a compile error.** `self.foo = tk.Text(…)`
then `self.foo.insert(…)` gives `Nil Python: Text has no method insert`. Note
the attribute NAME is irrelevant and was the first thing ruled out: `self.foo`
fails, and `self.text` holding a **Label** is fine. It is the TYPE name.

`from tkinter import Text` silences face C but leaves face A — the attribute is
still dynamic — so it is not a fix, only a quieter failure.

## The diagnostic points at the healthy half

Worth fixing alongside, because it cost the most time here. The failure surfaces
as:

```
AttributeError: 'Scrollbar' object has no attribute 'set'
```

`Scrollbar.set` is fine — it exists, and calling it directly works. The
offending expression is `self.text.yview` in the *other* argument of the same
statement. Anyone reading that message goes to the scrollbar, which is the one
part of the pair that is healthy.

## Repro

```python
# tkscroll.npy — expected: prints ok; actual: AttributeError on Scrollbar.set
from tkinter import Frame, Scrollbar, Text
import tkinter as tk

class F(Frame):
    def __init__(self, master):
        super().__init__(master)
        self.bar = Scrollbar(self, orient="vertical")
        self.text = Text(self, width=20, height=3)
        self.text.configure(yscrollcommand=self.bar.set)
        self.bar.config(command=self.text.yview)      # <-- fails here
        self.bar.pack(side="right", fill="y")
        self.text.pack(side="left", fill="both", expand=True)

root = tk.Tk()
f = F(root); f.pack(); root.update()
print("ok")
```

Swap `Text` for `Canvas` (and drop `wrap`) and it runs — that is the control.

## Scope of the damage

Any NilPy program that **stores or subclasses** a Text widget: every scrolled
text view, every editor pane, and [[feature-b-tkhtmlview-in-nilpy]], which is
blocked on this and cannot be written around — a Frame-based design needs
`text.yview` as a value (face A) and a Text-based design needs the base class
(face B). `~/songformatter` reaches it through tkhtmlview.

**Not a façade gap, and not fixable in `lib/pcl`.** Track B cannot rename
`tkinter.Text` (the application writes the Python name) nor `textfile.Text`
(standard Pascal's file type). The alias `TkTextWidget = Text` already exists at
`tkinter.pas:565` for the Pascal side and is unreachable from Python.

## Fix direction — for whoever holds Track A

Make the two by-name positions carry the RESOLVED class the way a local does,
rather than re-looking-up the bare name. The ordering subtleties are the ones
[[decide-class-namespace-scoping]] and `bug-nilpy-stdlib-name-binds-pascal-unit`
already record; this ticket adds that a **record** and a **class** can collide,
not just two classes, and that a `Text` record silently wins over a `Text` class.

## Found alongside, already fixed (Track B, not part of this ticket)

`Text` had no `yview` / `xview` / `yview_scroll` in `lib/pcl/tkinter.pas` at all
— `Canvas` has carried them since it was written. Added, and verified from
Pascal where a missing method is a hard compile error. That gap is real and
independent, but it is NOT the cause here: with it fixed, the direct call
`self.text.yview("moveto 0")` works and the bound-method-as-value still fails.

## There is already a test for this invariant — it just uses `Canvas`

`examples/tk/field_class_identity.npy` (in `make test-nilpy`) opens with:

> *A field assigned a QUALIFIED construction keeps its class — in any method, not
> only `__init__` — so calls on it resolve statically and bind keyword arguments.*

That is exactly face A, asserted and passing. It passes because every field in
it is a `Canvas` or a `Frame`. The invariant it defends is **false for `Text`**,
and the suite cannot see that because no case picks a name the RTL also uses.

So the cheap regression is a sibling case in that same file — a field assigned
`tk.Text(...)`, plus one `class H(tk.Text)` — and it is worth adding whatever
else is done here, because a colliding name is the one thing the existing test
was never pointed at.

## Gate

The repro above printing `ok`; `class H(tk.Text)` inheriting `insert`;
`make test-nilpy` green; self-host byte-identical. Add the `Text` cases to
`field_class_identity.npy` per the section above — this survived a `done` root
fix unnoticed precisely because nothing tested a colliding name.

## Resolution (2026-08-11) — one predicate, and the helper was already written

### The repro does not need tkinter, X11 or a display

Before touching anything, the collision was reduced to a 12-line Pascal unit and
6 lines of NilPy — a `Text = class` next to the RTL's `Text = record`, no
widgets involved. That made the edit/measure loop seconds instead of a headless
X server, and it gave a **control that removes the variable rather than
relabelling it**: the identical unit with the class renamed `Zext`.

| | `Text` (collides) | `Zext` (control) |
| --- | --- | --- |
| before | attribute dynamic, `class H(Text)` → *"H has no method Insert"* | both fine |
| after | `attribute: 15` / `base class: 17 11` | identical |

### The root — `IsClassType` asked the wrong ROW

```pascal
ci := FindUClass(lo2);                          { the FIRST row of that name }
if (ci >= 0) and (not UClsIsRecord[ci]) then Result := True;
```

`FindUClass` answers with the first row whatever it is, so testing
`not UClsIsRecord[ci]` on it says **False whenever a same-named record comes
first** — even though a class of that name also exists. The RTL's `Text` sits
ahead of `lib/pcl`'s `Text = class(Widget)`, so `IsClassType('Text')` was False
and every gate keyed on it stood down. That is the ticket's "one cause, three
faces", and it is one line.

### The helper for it already existed, wired to only three sites

`FindUClassNonRecord` (`symtab.inc:1171`) — *"the CLASS of that name, skipping
same-named RECORDS"* — was written for **this exact `Text` collision**, cites
`decide-class-namespace-scoping`, and its comment names the file record. It had
been wired into the construction intercept and the Pascal typecast branch. The
positions this ticket reports were left on plain `FindUClass`:

| site | face |
| --- | --- |
| `IsClassType` (symtab.inc) | the root predicate under all three |
| `PyParseClass` base-class lookup | B — inherited the record |
| the hoisted base-class lookup | B — the same, on the pre-pass path |
| `PyRecFromTokenIndex` | A — the field's recorded type |
| the qualified-construction arm (`self.t = tk.Text(...)`) | C — compile error |
| the annotation arm beside `IsClassType` | the ci disagreeing with the predicate that just said yes |

Textbook `normalise-dont-special-case.md`: the fix existed, and the siblings
were never grepped for. Six sites now share one rule.

### Verified

- The ticket's own repro compiles and prints **`ok`** under `xvfb-run`.
- `class H(tk.Text)` inherits `insert` and `shout()` runs; the `tk.Canvas`
  control beside it still works.
- The minimal collision repro matches its renamed control exactly, for both the
  attribute and the base class.

### Regression test — in the file that was already asserting this

Per the ticket's own section, the cases went into
`examples/tk/field_class_identity.npy` rather than a new file: it has asserted
this invariant since it was written and could not see the break, because every
field in it was a `Canvas` or a `Frame` — a name nothing else uses. Added: a
field from bare `Text(...)` and from qualified `tk.Text(...)` (separate lookups,
both were broken), a **bound method taken as a value** off that field (the thing
a dynamic receiver could not do, while a direct call on it worked — so a direct
call alone would not have caught it), and `class Editor(tk.Text)`.

**Confirmed it fails on the old compiler**, which is what makes it a regression
test rather than a passing example: `stable_linux_amd64/default/pinned` reports
*"Nil Python: Text has no method configure"* on it, and HEAD compiles it.

Gate: `tools/gate.sh quick` GREEN (self-host fixedpoint + FPC seed canary) +
`make test-nilpy`.

## Log
- 2026-08-11 — resolved, commit 32df43653.
