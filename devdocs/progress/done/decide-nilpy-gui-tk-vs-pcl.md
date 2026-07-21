---
summary: "RESOLVED 2026-07-21: keep the real Tcl/Tk embed on Linux (works); Windows = opt-in tk emulate/wrap via a platform include, later. Follow-up: feature-pcl-tk-windows-compat"
type: decide
prio: 25
status: resolved
---

# DECIDE — NilPy GUI: tk-face over PCL, or real Tcl/Tk embed? — **RESOLVED**

- **Type:** Track U (decision). Resolved 2026-07-21 by the user.
- **Outcome:** neither pure (A) nor pure (B) — a **platform split**, keep-what-works.
- Parent: [[feature-pcl-cross-platform-gui]]. Follow-up work:
  [[feature-pcl-tk-windows-compat]].

## Decision

`import tk` is satisfied inside `lib/pcl/tk.pas` by a **compile-time platform switch**:

```
{$ifdef WINDOWS}
  {$include windows-tk-compat.inc}   // opt-in emulate/wrap — stub now, fill later
{$else}
  // keep the existing real Tcl/Tk embed — it works, cheap system dep on Linux
{$endif}
```

- **Linux = keep the real Tcl/Tk embed** (`tk.pas` today). It works, it's mature, and
  libtcl/libtk is a cheap system package there. No refactor, no rip-out.
- **Windows = an opt-in emulate/wrap**, isolated in one include (`windows-tk-compat.inc`),
  stubbed now and filled later. This is where the Tcl/Tk DLL-swarm would otherwise bite,
  so Windows is the *only* place we wrap — the weirdness stays quarantined in one file.

Rationale for overriding the earlier (A) "tk-face over PCL" recommendation: **don't rip
working code.** The platform-include keeps Linux untouched and confines all Windows cost
to a single opt-in `.inc` — smaller, incremental, and it doesn't block anything.

## Superseded options
- **(A) thin tk-face over PCL everywhere** — rejected: needless rip of a working Linux
  embed.
- **(B) real Tcl/Tk embed everywhere** — rejected for Windows only (DLL swarm); kept for
  Linux.

Re-filed as the low-prio Track W follow-up [[feature-pcl-tk-windows-compat]].
