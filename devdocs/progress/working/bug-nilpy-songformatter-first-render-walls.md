---
track: N
prio: 75
type: bug
---

# songformatter: the walls between "GUI builds" and "first document renders"

## 2026-07-29: the document RENDERS — walls below this line are cleared

The app now starts, builds the UI, loads the last-opened song and shows it in
the editor (screenshot verified under Xvfb). What fell on the way, all landed
and gated:

| wall | cause | fix |
| --- | --- | --- |
| `analyze_song_key` "died" on `song_text.split` | NilPy had **no `str.replace`**, so `song_text = song_text.replace(...)` fell into the unresolved-optional-import fallback, which TAINTS THE ASSIGNED NAME — every later `song_text.<anything>` raised | added replace + 13 more str methods (f5ee614) |
| `c.setStrokeColorRGB(*rgb)` | no call-site `*` unpack on a METHOD | `PyStarUnpackMethodArgs` (f5ee614) |
| `root.title("x")` bound to `str.title` | new str methods shadowed widget methods on a variant receiver | `title`/`count` lose to a declared class method (f5ee614) |
| every `command=`/`bind` callback | unannotated defs return a Variant through a hidden pointer; the callable typedefs said `: Int64`, so the callee's epilogue wrote 16 bytes to a stale address — SIGSEGV on RETURN | Variant-returning typedefs (45fc761) |
| zero-argument callbacks | `pycallback_call0 := f0` assigns the POINTER; a bare procedural name is not a call here | `f0()` (45fc761) |
| `root.mainloop()` | no `mainloop` on a widget — closed-world dispatch fell to a nil code pointer, SIGSEGV with no diagnostic | added (45fc761) |
| preview never redrew | no `after`/`after_idle`/`after_cancel` in the facade | added, with one-shot slots + a free list (45fc761) |
| — | unhandled exceptions printed no message | handler now prints `<ClassName>: <Message>` (582f58e) — this is what found the first wall in one run instead of a marker bisect |

Also added: `see`, `mark_set`, `lift`, `lower_`, `deiconify`, `iconify`,
`clipboard_get/clear/append`; `configure` no longer burns a callback slot on its
DEFAULT postcommand; `bgerror` prints to stderr like CPython instead of popping
a modal dialog.

**What is left** (both filed separately, this ticket stays open behind them):
- [[bug-nilpy-tk-pxxcb-invalid-command-name]] — Tk's error dialog still appears.
- [[bug-nilpy-callable-in-local-var-call-does-nothing]] — `cb = handler; cb(x)`.
### 2026-07-29 (later): the redraw path runs

Since the nested-def fix the preview/analysis code really executes, and each
wall now surfaces as a NAMED error instead of a crash (the nil-callee guard and
the link-time `@proc` check). Cleared in order:

| wall | fix |
| --- | --- |
| jump to address 0 in the redraw | `Canvas.delete("all")` did not exist (only `delete_all`), so the standard spelling was a None attribute |
| `TypeError: expected a number, got str` from `settings.getF` | `float(<variant holding a str>)` routed to `pyfloat_ofint` from the STATIC type; a variant needs the run-time split — added `pyfloat_any` |
| `unsupported f-string format spec ".0%"` | added Python's `%` presentation type (x100, fixed precision, `%` suffix), verified against CPython |

Now dies inside `KeyAnalysisResult.to_text` / `DetectorResult.to_text`
(`pystr_join` / `TPyList.at` on the stack) — so the key analysis itself
completes and the failure is in rendering it. Minimal genexpr-of-method-calls
and keyword-arg-in-genexpr repros do NOT reproduce it; the next step is the
dataclass shapes those two use (`candidates[:5]` slicing a list of objects,
`field(default_factory=list)` members).

- [[bug-nilpy-zero-param-lambda-cannot-call-a-def]] — this is what leaves the
  preview blank and the status bar on `Key: unknown`: the redraw is armed as
  `cv.after(120, lambda: draw(...))` and a zero-parameter lambda cannot call a
  compiled def.


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
