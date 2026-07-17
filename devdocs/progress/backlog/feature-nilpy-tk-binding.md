---
summary: "Thin Tcl/Tk embed for pxx (lib/pcl/tk.pas) + a tkinter-shaped NilPy surface — v1 landed"
type: feature
prio: 45
---

# Thin Tcl/Tk binding (`import tk`)

- **Type:** feature (Track B — library; `lib/pcl/tk.pas`). Enables the NilPy IDE demo
  ([[feature-demo-nilpy-ide]], Track E).
- **Status:** backlog — **v1 (embed core) LANDED**, surface work remains.
- **Opened:** 2026-07-17.

## Approach

The whole GUI is Tcl/Tk **command strings** through `TkEval` — the CPython-tkinter model
minus tkinter's weight. `lib/pcl/tk.pas` binds the system `libtcl8.6`/`libtk8.6` sonames
with hand `external` clauses (no `-dev` headers, no C-import-registry change). Thin by
construction: Tk does all widget/layout/event work.

## v1 — LANDED (commits `f2dd8206`, tk.pas StrPas fix)

- `TkInit` / `TkEval` / `TkMainLoop` over the Tcl/Tk C API. `DT_NEEDED` pulls
  libtcl/libtk; runs under `xvfb`.
- `examples/tk/hello.npy`: `import tk` from Nil-Python opens a window + runs the event
  loop. Proven end-to-end.
- **Event model settled — POLL, no C trampoline.** A widget writes a Tcl variable
  (`-command {set action run}`); NilPy polls it with `TkEval("update")` + `TkEval("set
  action")` in its own loop. Proven working. This keeps the wrapper thin — no
  `Tcl_CreateObjCommand`/callback plumbing, pure `TkEval`.
- **Found + filed along the way:** [[bug-pascal-ansistring-cast-of-cdecl-call-result]]
  (silent, the StrPas fix), [[feature-nilpy-break-continue]] (NilPy loop-control gap).

## Remaining

1. **tkinter-shaped convenience surface** — thin helpers so common Python tk snippets run
   (e.g. `Text`, `Button`, `pack`, `bind`, `mainloop` mapping to one `TkEval` each). Stays
   thin: name→command mapping, not a widget reimplementation. Where NilPy's v1 subset
   limits compat (kwargs, `str+str`, callbacks), that is a NilPy limit, not the wrapper.
2. **`ttk` themed widgets** — one `TkEval("ttk::style ...")` away; closes most of the
   dated-look gap for free.
3. **Gate smoke** — an `xvfb`-wrapped hello smoke wired into `test-nilpy`/`lib-test`
   (testmgr already models the `xvfb` resource). Auto-close via `after` so it terminates.

## Acceptance

- v1: `import tk` opens a window from NilPy and runs the loop (DONE).
- Surface: a representative tkinter-style snippet (label + button + poll loop) runs.
- A gated `xvfb` smoke; `make test-nilpy` green.

## Non-goals

- Not full tkinter parity — the common subset, thin.
- Not a C-callback event system — the poll model is the deliberate thin choice.
