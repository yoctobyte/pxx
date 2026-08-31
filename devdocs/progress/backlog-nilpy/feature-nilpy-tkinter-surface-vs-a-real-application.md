---
track: N
prio: 60
type: feature
blocked-by: []
summary: "The tkinter façade is built and now genuinely gated (it runs under Xvfb), but its widget/option surface has never been proven against a real application. songformatter's GUI is the forcing target: tkinter.font metrics (descent/measure), Canvas.create_text anchoring, Notebook, PanedWindow. Measurable for the first time now that a running harness exists."
---

# Prove the tkinter surface against a real application

- **Type:** feature (NilPy stdlib surface) — **Track N**.
- **Split out of** [[feature-nilpy-tkinter-facade]] on 2026-08-17, whose stated
  gate ("a `.npy` GUI case under xvfb: a `command=` callback that fires and a
  Canvas drawing") is now met. This is the part of that ticket's scope which the
  gate does **not** cover, kept as its own item rather than left as a vague tail
  on a resolved one.

## Why this is a separate ticket, not a doubt about the last one

The façade (`lib/pcl/tkinter.pas`, 2453 lines) works, and as of `f1caa44fb`
three `.npy` examples run under Xvfb with diffed output, so callbacks, traces,
canvas drawing and widget paths are all genuinely asserted.

What that does **not** establish is *breadth*. The examples exercise the
constructs someone wrote an example for — which is the same self-selection
problem [[feature-nilpy-thirdparty-libraries-as-targets]] is built around: code
written here can unconsciously avoid what the façade does not support.

## The forcing target, and the specific surface

songformatter's GUI (see [[feature-demo-songformatter-pxx-target]]), because it
is a real application nobody wrote to fit this façade. The surface its preview
path needs, from the parent ticket's own list:

- **`tkinter.font` metrics** — `descent` and `measure`. Load-bearing: the
  parallel-canvas preview places text by measured width and baseline, so a wrong
  or missing metric is a silently misaligned render, not an error.
- **`Canvas.create_text`** with `anchor=` and a `font=(family, size)` tuple.
- **`Notebook`**, **`PanedWindow`** — declared, but not exercised by any running
  example.
- `Canvas` `coords` / `delete` / `scrollregion` / `xview`/`yview`, `Text`,
  `Menu`, `PhotoImage`, `place` geometry.

## Method — do NOT just read the unit

Compile and RUN, under Xvfb, and diff against CPython's own tkinter where the
value is observable (font metrics are numbers: CPython is a real oracle for
`measure`/`descent`, and the repo already has a tkhtmlview oracle-diff doing
exactly this). A declared method that returns a wrong number is the failure mode
to expect here — the same class as the parent ticket's real finding, where
everything compiled and nothing ran.

Extend `examples/tk/` and the Xvfb block the parent ticket added, rather than
starting a new harness.

## Gate

The new cases run under Xvfb with diffed output, `tools/gate.sh quick` green,
and — for anything with a numeric answer — agreement with CPython's tkinter
rather than with a recorded snapshot of our own output.

Keep the "can it fail?" check the parent ticket used: corrupt an expected file
once and confirm the recipe exits nonzero. A GUI test that cannot fail is worse
than none.
