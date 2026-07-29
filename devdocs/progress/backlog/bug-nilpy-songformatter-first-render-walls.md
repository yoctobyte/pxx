---
track: N
prio: 75
type: bug
---

# songformatter: the walls between "GUI builds" and "first document renders"

The application compiles, starts, and builds its ENTIRE interface — menus,
toolbar, notebooks, the settings editor and the document editor widget. It then
dies rendering the first (empty) document.

Where it stands, walking the startup path:

```
load_session() -> create_document_tab(select=True)
  FormatText(...)                     ok
  documents_notebook.add(doc, ...)    ok
  doc.set_document_text("")           -> convert_text()
    self.get_document_text()          ok
    analyze_song_key(raw_text)        <- DIES HERE (raises; no message)
```

`analyze_song_key` is songformatter's own `key_analysis.analyze_key` wrapper, on
an EMPTY string. key_analysis.py compiles and imports cleanly on its own, so the
failure is in what it does with empty input, or in something it calls that this
path reaches first.

## Fixed on the way here (this ticket is what is LEFT)

tkinter gained `Notebook` (the whole multi-document UI), `Button`, `Separator`,
`Toplevel`, `protocol`, `PanedWindow.sashpos`, `Widget.children` (+ pylib's
`TPyDict.clear`), `Frame(padding=)`, `Label(textvariable=)`, `config(menu=)`,
`add_cascade`, `postcommand`. Two frontend bugs also fell out: a variant hole in
a KEYWORD CONSTRUCTION was filled with a raw ordinal (the callee dereferences a
by-reference variant — `tk.Label(root, textvariable=sv)` segfaulted skipping
`font`), and a bound method captured inside an imported module
([[bug-nilpy-settings-editor-segfaults-on-bound-method-field]], fixed by sis).

## Method that is working

Compile, run under Xvfb, and when it dies copy the app to a scratch directory
and insert `print` markers — the unhandled-exception handler prints no message
and no stack, so the marker bisect is what locates the statement. Each wall so
far has been one missing façade method or one silent frontend gap.

## Worth fixing first, separately

The unhandled-exception handler prints `Unhandled exception` and nothing else
(`compiler/exception_emit.inc`). Printing the exception's Message — and ideally
the class — would have saved most of the bisecting on this ticket.

## Gate

`make test-nilpy`, plus songformatter's window actually opening under Xvfb with
one empty document.
