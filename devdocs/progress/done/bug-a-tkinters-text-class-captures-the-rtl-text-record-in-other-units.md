---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`uses tkinter, configparser;` no longer compiles: lib/pcl's `Text = class(Widget)` wins the `Text` lookup inside lib/rtl/configparser.pas, whose own `var f: Text` means the RTL FILE record. Five lines of Pascal, no NilPy involved — the class-over-record preference reaches Pascal declarations in units that never named tkinter."
status: done
owner: agent-an-night
---

# `Text` the widget captures `Text` the file record in an unrelated unit

Found while checking the real consumer of [[feature-b-tkhtmlview-in-nilpy]]
(`~/songformatter/SongFormatter.py`), against
`stable_linux_amd64/default/pinned` **v339 / f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c**.

## Repro — five lines, pure Pascal

```pascal
program cp3;
uses tkinter, configparser;
begin
  WriteLn('both ok');
end.
```

```
error: no overload of Assign matches these arguments
  argument types: (class, AnsiString)
  candidates:
    Assign(record, AnsiString)
  near: Assign  f  path  >>>  Reset
```

The failing line is **`lib/rtl/configparser.pas:353`**, inside the RTL's own
`ConfigParser.read`:

```pascal
function ConfigParser.read(const path: AnsiString): Boolean;
var f: Text; line, text: AnsiString; ok: Boolean;   { <- Text = the FILE record }
begin
  ...
  Assign(f, path);
```

`uses configparser;` **alone compiles**. Adding `tkinter` to a `uses` clause
somewhere else in the program is the entire difference — configparser never
names tkinter, and `lib/pcl/tkinter.pas`'s `Text = class(Widget)` still reaches
it, which is [[bug-pascal-uses-is-transitive]] supplying the ammunition.

The NilPy spelling breaks identically (`import tkinter as tk` +
`import configparser`), but Pascal alone is the smaller repro and says where the
lookup is.

## Why this is worth a high prio

- It is a **shipped RTL unit** that stops compiling because of what some other
  unit in the program declares. Any program combining a Tk UI with
  `configparser` — i.e. an app with a GUI and a settings file, which is a very
  ordinary shape — cannot build.
- It bites at a distance: the error names configparser, and nothing in
  configparser is wrong.
- It very likely generalises. `Text` is not the only name lib/pcl and lib/rtl
  share, and `Assign` is only the first call that happens to be typed strictly
  enough to notice.

## Probable cause — and the reason it looks new

[[bug-nilpy-text-class-name-binds-the-rtl-file-record]] fixed the opposite
polarity: `Text` in NilPy bound to the RTL record when the widget class was
meant, and the fix wired `FindUClassNonRecord` ("the CLASS of that name,
skipping same-named RECORDS") into six lookup sites that had been on plain
`FindUClass`. That is the right answer for a NilPy class position. This ticket is
what it looks like when the same preference is applied where a **Pascal type
declaration** asks the question, and the honest answer there is the record.

I did not bisect it onto that commit — the archived pins need their contemporary
`lib/builtin` to run, so the old binaries would not compile the probe at all.
Treat the attribution as the leading hypothesis, not as measured, and confirm it
before writing it into the fix.

The real disease underneath is the flat namespace
([[decide-class-namespace-scoping]]), which `lib/pcl/tkinter.pas` already
documents at its `TkTextWidget` / `NewText` workaround: *"this is a workaround
for the flat namespace, and it goes away when that does."* Per
`root-cause-over-microfix.md` this is a case where the count of mechanisms
serving one concept (three now: the alias type, the factory function, and the
non-record preference) is the signal — the microfix is a fourth.

## Not what blocks songformatter

Worth stating because it is easy to misread: `SongFormatter.py` now gets **past**
the `from tkhtmlview import HTMLScrolledText` line — the port works — and dies
here instead, in an RTL unit, on a name that has nothing to do with either.

## Fixed 2026-08-15 — the visibility rule, not a fourth mechanism

The ticket's leading hypothesis was right about the site and right to warn
against a microfix. `FindUClassNonRecord` — the "prefer the CLASS over a
same-named RECORD" predicate that
[[bug-nilpy-text-class-name-binds-the-rtl-file-record]] wired into six lookup
sites — scanned the class table **flat and global**, with no `DeclVisible`
filter at all. So it answered for `lib/rtl/configparser.pas`, a unit that never
names tkinter, and `var f: Text` became the widget.

Preferring the class is still correct where a NilPy class position asks. It was
only ever wrong because it answered for scopes that **cannot see the class**.
So the fix is the rule that already governs its sibling `FindUClass`: filter by
`DeclVisible`, then rank the survivors by `UsesRankOf` (latest-named unit wins,
the scope's own declaration outranks its imports) — the same two lines added to
five name tables earlier today under
[[bug-p-scope-hiding-covers-routines-but-not-types-and-classes]]. No fourth
mechanism: this predicate now obeys the same rule as everything around it, and
lib/pcl's `TkTextWidget` alias / `NewText` factory stay exactly as they are.

Confirmed at HEAD before and after, both polarities:

- `uses tkinter, configparser;` — was the ticket's error at
  `configparser.pas:353`, now builds and runs. Same for the NilPy spelling
  (`import tkinter as tk` + `import configparser`).
- The opposite polarity still holds: `class H(tk.Text)` subclasses the WIDGET,
  and `examples/tk/field_class_identity.npy` / `kwargs.npy` still compile —
  the three faces the earlier ticket fixed are untouched.
- `uses tkinter, configparser, sysutils, classes, strings;` builds, which is the
  "it very likely generalises" line answered: the mechanism is fixed, not the
  one name.

New `examples/tk/uses_tkinter_and_configparser.pas` in `test-nilpy` and
`test-core` (compiled, not run — tkinter needs an X display; and in
`examples/tk/` rather than `test/` for the documented reason that a source in
`test/` resolving `tk` picks up `test/strings.pas` first).

`gate.sh quick` + self-host fixedpoint GREEN, FPC seed canary included.

Note the root disease named above — the flat namespace,
[[decide-class-namespace-scoping]] — is genuinely narrower now than when this
was filed: with `uses` non-transitive and every name table ranking by clause
order, "flat" only bites between units that DO see each other. That decision is
still worth taking; it is no longer what makes this class of bug reachable.

## Log
- 2026-08-15 — resolved, commit 8c8a95a69.
