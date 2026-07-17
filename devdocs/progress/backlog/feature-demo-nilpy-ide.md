---
summary: "Landmark demo: a minimal IDE in Nil-Python via import tk — max functionality, minimal code"
type: feature
prio: 40
blocked-by: [feature-nilpy-tk-binding, feature-nilpy-break-continue]
---

# Landmark demo — a minimal IDE in Nil-Python (`import tk`)

- **Type:** feature / demo (Track E — app built with pxx; **Track B file-ownership**,
  `feature-demo-*` auto-tags E). Build with the compiler, never rebuild it.
- **Status:** backlog (blocked on the tk surface + NilPy loop-control)
- **Opened:** 2026-07-17, from the "landmark demo" design discussion.
- **Related:** [[feature-nilpy-tk-binding]] (the GUI substrate), [[project_eliah_ilja_ide]]
  (the Pascal IDE — the boilerplate weight this demo deliberately undercuts).

## The thesis

**Minimal code, maximum functionality.** A full-enough editor/IDE in a few hundred lines
of Nil-Python, because `import tk` pushes all widget/layout/event work into mature Tcl/Tk.
This is `ir-as-substrate` applied to *apps*: keep the app thin, lean on a proven external
lib. The contrast with Eliah/Ilja (Pascal/LCL: class hierarchy + RTTI streaming + LFM +
event objects, hundreds of lines before "hello window") **is** the point — same
functionality, an order of magnitude less code.

## Shape (all `TkEval` command strings + NilPy)

- **Editor** — Tk `text` widget (`text .ed -wrap none`; `.ed insert`, `.ed get`).
- **Open / Save** — NilPy file I/O (already works) + Tk `tk_getOpenFile`/`tk_getSaveFile`.
- **Run button — dogfood.** Spawn `pxx` on the buffer, capture stdout into an output
  pane. A pxx-compiled IDE that compiles pxx: self-referential landmark.
- **Syntax highlight** — Tk text tags (`.ed tag add kw ...; .ed tag configure kw
  -foreground blue`).
- **Event loop** — the proven **poll model**: widgets write Tcl vars, NilPy polls via
  `TkEval("update")`; no C callbacks. (Cleaner once [[feature-nilpy-break-continue]] lands
  — today it needs flag-variable loops.)

## Acceptance

- A NilPy program (`examples/tk/ide.npy`) opens an editor window, loads/saves a file, and
  runs the current buffer through pxx with output shown — under `xvfb` for a headless
  smoke, interactively on a real display.
- Line count stays small enough to *be* the flex (target: the core IDE well under ~400
  lines of NilPy).
- Build with `$(PXX_STABLE)`; `make demos`/`lib-test` smoke where wired.

## Non-goals

- Not a serious/native-looking IDE — that's the GTK path with its boilerplate; this is the
  minimalism showcase (Tk, `ttk` for a modern-enough look).
- Not a compiler/frontend change — a gap the app hits (NilPy feature, tk surface) is filed
  to the owning lane (N / B), not fixed under E.
