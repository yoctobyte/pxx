---
summary: "NilPy tk on Windows — quarantine the Tcl/Tk-DLL-swarm problem behind a {$ifdef WINDOWS} include in tk.pas; emulate/wrap, stub now fill later. Linux keeps the real embed"
type: feature
track: W
prio: 25
blocked-by: [feature-port-windows-pe]
---

# PCL/NilPy — Windows tk compatibility (opt-in emulate/wrap)

- **Type:** feature (**Track W** — Windows campaign; file-owned by Track B, `lib/pcl`).
  Gate = `make lib-test` green on Linux (Linux path unchanged); Windows tk = Wine-smoke
  best-effort.
- **Status:** backlog. Implements the resolution of [[decide-nilpy-gui-tk-vs-pcl]].
  Blocked-by [[feature-port-windows-pe]] (needs a Windows binary to run at all).
- **Owner:** —
- **Opened:** 2026-07-21.

## What

NilPy `import tk` must "just work" on Windows too. The decision
([[decide-nilpy-gui-tk-vs-pcl]]) is a **compile-time platform switch inside
`lib/pcl/tk.pas`** — Linux keeps the real Tcl/Tk embed (works, cheap system dep);
Windows gets an opt-in emulate/wrap in one isolated include, so the Tcl/Tk DLL-swarm
never touches the zero-dep Windows binary.

```
{$ifdef WINDOWS}
  {$include windows-tk-compat.inc}   // this ticket — stub now, fill later
{$else}
  // existing real Tcl/Tk embed, untouched
{$endif}
```

## Shape (deliberately incremental)

- **Now:** land the `{$ifdef WINDOWS}` split + a `windows-tk-compat.inc` **stub** that
  compiles and gives a clear "tk-on-Windows not yet implemented" at the tk-call boundary.
  Zero Linux impact (the else-branch is today's code verbatim).
- **Later:** fill the include — most cheaply as a thin tk-shaped veneer over the Win32
  widgetset ([[feature-pcl-win32-widgetset]]), so NilPy tk on Windows rides the same
  zero-dep user32/gdi32 path as Pascal GUI. (Alternative: bundle libtcl/libtk — rejected,
  that's the swarm.)

## Explicitly NOT

- Not a Linux change — the real Tcl/Tk embed stays exactly as-is.
- Not gated on real-Windows parity (no Windows box; Wine-smoke only, best-effort).

## Acceptance

- Linux: `tk.pas` builds and the NilPy IDE / `examples/tk/*.npy` run **byte-unchanged**
  (else-branch = today's embed). `make lib-test` green.
- Windows stub: `--target=x86_64-windows` compiles `tk.pas` (takes the ifdef branch) and
  fails gracefully with a clear message at first tk use — no silent breakage, no libtcl
  dependency pulled into the PE.
