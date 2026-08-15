---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`uses tkinter, configparser;` no longer compiles: lib/pcl's `Text = class(Widget)` wins the `Text` lookup inside lib/rtl/configparser.pas, whose own `var f: Text` means the RTL FILE record. Five lines of Pascal, no NilPy involved — the class-over-record preference reaches Pascal declarations in units that never named tkinter."
status: open
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
